# frozen_string_literal: true

class Room < ApplicationRecord
  # Сроки жизни исчезающих сообщений, которые вообще можно выбрать. Произвольное число с
  # клиента не берём: секунда превратила бы чат в мигание, а год — в обычную переписку.
  TTL_OPTIONS = [300, 3_600, 86_400, 604_800].freeze
  MAX_CHANNELS = 20

  has_many :room_memberships, dependent: :destroy
  has_many :users, through: :room_memberships
  has_many :messages, dependent: :destroy
  has_many :scheduled_messages, dependent: :destroy
  has_many :chat_folder_rooms, dependent: :destroy
  # Каналы внутри группы: те же комнаты, но подчинённые. Уносим вместе с родителем —
  # канал без группы недостижим, а его переписка продолжала бы занимать место.
  has_many :channels, class_name: "Room", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
  belongs_to :parent, class_name: "Room", optional: true
  # Создатель группы. У лички владельца нет, у старых групп его тоже нет — связь опциональная.
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :saved_for, class_name: "User", optional: true
  # Аватар группы: файл, загруженный создателем.
  has_one_attached :avatar

  # Личка создаётся с dm_key, группа — без него; личная «Избранное» не является ни тем, ни другим.
  def group?
    dm_key.blank? && !saved?
  end

  # Канал группы: отдельная переписка внутри неё, состав наследуется от родителя.
  def channel?
    parent_id.present?
  end

  def saved?
    saved_for_id.present?
  end

  # Персональная комната «Избранное». Создаётся лениво — и из списка чатов, и при сохранении
  # чужого сообщения, поэтому живёт здесь, а не в одном из двух контроллеров.
  def self.saved_room_for(user)
    create_or_find_by!(saved_for: user).tap { |room| room.add_member(user) }
  end

  def direct?
    dm_key.present? && !saved?
  end

  def peer_for(user)
    users.find { |member| member.id != user.id }
  end

  # Для лички одна блокировка ставит паузу на общение в обе стороны. Группы и «Избранное» не затрагиваются.
  def block_state_for(user)
    return "none" unless direct?

    peer = peer_for(user)
    return "none" unless peer
    return "blocked_by_me" if UserBlock.exists?(blocker_id: user.id, blocked_id: peer.id)
    return "blocked_me" if UserBlock.exists?(blocker_id: peer.id, blocked_id: user.id)

    "none"
  end

  def direct_chat_blocked_for?(user)
    block_state_for(user) != "none"
  end

  # Переименовать группу, сменить её аватар, исключить участника и удалить её у всех
  # может только создатель. Звать новых участников по-прежнему может любой.
  def owned_by?(user)
    owner_id.present? && owner_id == user.id
  end

  # Картинка группы: загруженный файл в приоритете, иначе — ссылка, если её проставили руками.
  # proxy, а не redirect — по той же причине, что и у вложений (ссылка собирается вне запроса).
  def avatar_image_url
    return avatar_url if !avatar.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_url(avatar)
  end

  # Имя диалога с точки зрения конкретного юзера:
  # для группы — заданное имя, для лички — имя собеседника.
  def display_name_for(user)
    return "Избранное" if saved? && saved_for_id == user.id
    return name if name.present?

    peer = users.find { |member| member.id != user.id }
    return peer.name if peer

    # Собеседник удалил личку у себя — в составе его больше нет, имя берём из переписки.
    messages.find { |message| message.user_id != user.id }&.user&.name || "Диалог"
  end

  def add_member(user, visible: true)
    # Валидация уникальности срабатывает раньше DB-ограничения, поэтому create_or_find_by!
    # на уже существующем участнике поднимал RecordInvalid. Сначала читаем существующую связь.
    membership = room_memberships.find_or_create_by!(user: user) { |created| created.visible = visible }
    membership.update!(visible: true) if visible && !membership.visible?
    # Состав канала повторяет состав группы: приглашённый в группу получает доступ ко всем
    # её каналам сразу, иначе он видел бы в шапке вкладки, в которые не может зайти.
    channels.each { |channel| channel.add_member(user, visible: visible) }
    membership
  end

  # Ссылка-приглашение. Токен заводится лениво — по нажатию «пригласить по ссылке», а не всем
  # группам подряд: у большинства чатов приглашения так и не появляются.
  def ensure_invite_token!
    return invite_token if invite_token.present?

    update!(invite_token: SecureRandom.urlsafe_base64(18))
    invite_token
  end

  def revoke_invite_token!
    update!(invite_token: nil)
  end

  # Когда истечёт следующее сообщение этой комнаты. Считается в момент отправки, а не чтения:
  # смена настройки не должна задним числом двигать сроки уже отправленного.
  def message_expiry_at
    return if ttl_seconds.blank?

    ttl_seconds.seconds.from_now
  end

  # Подметание просроченных исчезающих сообщений. Джоба удаляет их в реальном времени, но
  # очередь демо живёт в памяти процесса и не переживает его перезапуск — поэтому то же самое
  # делается на открытии комнаты, и человек никогда не видит сообщение, чей срок уже вышел.
  def sweep_expired_messages!
    messages.expired.with_chat_payload.find_each do |message|
      message.soft_delete!
      broadcast_message(message)
    end
  end

  # Кто из участников успел прочитать сообщение: отметка прочтения у каждого своя, и по ней
  # же считается «прочитано» у галочек. Автора в списке нет — его собственное сообщение
  # прочитанным им не считается.
  def readers_of(message)
    room_memberships
      .includes(:user)
      .where.not(user_id: message.user_id)
      .where(last_read_at: message.created_at..)
      .sort_by { |membership| membership.last_read_at }
  end

  def membership_for(user)
    room_memberships.find_by(user_id: user.id)
  end

  # Непрочитанные для юзера: чужие сообщения новее его last_read_at (или все, если ещё не читал).
  # Удалённые и скрытые блокировкой не считаем — иначе бейдж зовёт в чат, где показывать нечего,
  # и расходится со списком чатов, который считает то же самое одним запросом на все комнаты.
  def unread_count_for(user)
    scope = messages.visible.where.not(user_id: user.id)
                    .where.not(user_id: UserBlock.where(blocker_id: user.id).select(:blocked_id))
    last_read_at = membership_for(user)&.last_read_at
    scope = scope.where("messages.created_at > ?", last_read_at) if last_read_at
    scope.count
  end

  # Сколько непрочитанных упоминаний в комнате: считается по тем же границам, что и unread_count,
  # иначе бейдж «@» звал бы в чат, где упоминание уже прочитано.
  def mention_unread_count_for(user)
    scope = messages.visible.mentioning(user).where.not(user_id: user.id)
                    .where.not(user_id: UserBlock.where(blocker_id: user.id).select(:blocked_id))
    last_read_at = membership_for(user)&.last_read_at
    scope = scope.where("messages.created_at > ?", last_read_at) if last_read_at
    scope.count
  end

  # Когда собеседник(и) в последний раз читали — для галочек «прочитано» у автора.
  # Для лички это ровно один собеседник; max корректно и для группы («кто-то прочитал»).
  def peer_last_read_at_for(user)
    room_memberships.where.not(user_id: user.id).maximum(:last_read_at)
  end

  # Рассылка сообщения подписчикам комнаты. Живёт здесь, потому что отправляют и канал
  # (текст), и REST-контроллер (вложения, пересылка) — форма кадра должна быть одна.
  def broadcast_message(message, client_message_id: nil)
    users.find_each do |recipient|
      payload = message.as_chat_json(viewer: recipient)
      # Локальный id нужен только автору, поэтому не раскрываем его остальным участникам.
      payload[:client_message_id] = client_message_id if client_message_id.present? && recipient.id == message.user_id
      ChatChannel.broadcast_to([self, recipient], payload)
    end
  end

  # from: — автор события. Тем, кто его заблокировал, событие не уходит: раз содержимое
  # его сообщений мы прячем, то и «печатает…» от него показывать нельзя.
  def broadcast_chat_event(payload, from: nil)
    blocked_by = from ? UserBlock.where(blocked_id: from.id).pluck(:blocker_id) : []

    users.find_each do |recipient|
      next if blocked_by.include?(recipient.id)

      ChatChannel.broadcast_to([self, recipient], payload)
    end
  end

  # Единый путь публикации для websocket, HTTP и отложенной отправки.
  def publish_message(message, client_message_id: nil)
    reveal_to_members!
    broadcast_message(message, client_message_id: client_message_id)
    notify_activity(except: message.user)
    notify_incoming(message)
  end

  # Получатель увидит личку только с первым отправленным сообщением. Обновляем все связи:
  # это также покрывает отправку, пересылку и отложенное сообщение в ранее пустую комнату.
  def reveal_to_members!
    room_memberships.where(visible: false).update_all(visible: true, updated_at: Time.current)
  end

  # Повод для системного уведомления: всем, кроме автора, шлём «что и от кого пришло».
  # Имя чата считается под каждого получателя отдельно — у лички его нет в БД.
  #
  # Приглушённому чату кадр всё равно уходит: по нему клиент подтягивает пропущенное сообщение,
  # если WS-кадр комнаты потерялся при переподключении. Молчать должен звук и системное окно,
  # а не доставка, поэтому решение вынесено в поле notify.
  def notify_incoming(message)
    mentioned_ids = message.mentioned_user_ids
    memberships = room_memberships.index_by(&:user_id)

    users.reject { |member| member.id == message.user_id || message.hidden_from?(member) }.each do |member|
      mentioned = mentioned_ids.include?(member.id)

      UserChannel.broadcast_to(member, {
        type: "incoming",
        room_id: id,
        room_name: display_name_for(member),
        author_name: message.user.name,
        preview: message.preview_text,
        mentioned: mentioned,
        # Упоминание пробивает приглушённый чат — как в Discord. Тихая отправка не пробивается
        # ничем: её смысл в том, что отправитель сам решил не будить получателя.
        notify: (mentioned || !memberships[member.id]&.muted?) && !message.silent?
      })
    end
  end

  # Пинок «список чатов изменился» тому, кто в комнате уже не состоит: вышедшему из группы,
  # исключённому создателем, всем участникам снесённой группы. notify_activity их не достанет —
  # оно ходит по текущим участникам, а их к этому моменту уже нет.
  def self.notify_rooms_changed(user)
    UserChannel.broadcast_to(user, {type: "rooms_changed"})
  end

  # Пинаем персональный UserChannel участников, чтобы их список чатов/бейдж непрочитанных
  # обновился в реалтайме, даже если конкретный чат у них сейчас не открыт.
  # only: — только этому юзеру; except: — всем участникам, кроме него.
  def notify_activity(only: nil, except: nil)
    members = users.to_a
    members = members.select { |member| member.id == only.id } if only
    members = members.reject { |member| member.id == except.id } if except
    members.each { |member| UserChannel.broadcast_to(member, {type: "rooms_changed"}) }
  end
end
