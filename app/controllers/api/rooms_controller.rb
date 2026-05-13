# frozen_string_literal: true

module Api
  class RoomsController < BaseController
    MAX_ROOM_NAME_LENGTH = 120
    MAX_GROUP_MEMBERS = 100
    # GET /api/rooms — список диалогов текущего юзера (левая панель).
    def index
      # Не preload'им messages: для одной строки списка нужна только последняя запись, а загрузка
      # всей истории каждого диалога росла вместе с чатом и быстро съедала память процесса.
      rooms = current_user.visible_rooms.includes(:users, :owner).to_a
      render json: room_summaries(rooms)
    end

    # PATCH /api/rooms/:id/ttl { ttl_seconds: } — исчезающие сообщения.
    # Право есть у любого участника, а не только у создателя: это настройка самой переписки,
    # и в личке «владельца» у неё нет вовсе. Уже отправленные сообщения не трогаем —
    # у каждого свой срок, проставленный в момент отправки.
    def update_ttl
      room = current_user.rooms.find(params[:id])
      return render json: {error: "not_supported"}, status: :unprocessable_entity if room.saved?

      ttl = params[:ttl_seconds].presence && params[:ttl_seconds].to_i
      return render json: {error: "invalid_ttl"}, status: :unprocessable_entity if ttl && !Room::TTL_OPTIONS.include?(ttl)

      room.update!(ttl_seconds: ttl)
      # Настройка общая для комнаты: остальные участники должны увидеть её без перезахода.
      room.notify_activity
      render json: {room_id: room.id, ttl_seconds: room.ttl_seconds}
    end

    # GET /api/rooms/:id
    def show
      room = current_user.rooms.find(params[:id])
      render json: room_summary(room)
    end

    # POST /api/rooms { target_external_id:, target_name:, target_avatar_url: }
    # Найти-или-создать личку между текущим юзером и целевым (кнопка «Написать»).
    def create
      target = User.upsert_from_external(
        external_id: params[:target_external_id],
        name: params[:target_name],
        avatar_url: params[:target_avatar_url],
      )
      return render json: {error: "target_required"}, status: :unprocessable_entity unless target
      return render json: {error: "cannot_message_self"}, status: :unprocessable_entity if target.id == current_user.id

      room = find_or_create_dm(current_user, target)
      # Пустая личка видна только тому, кто её открыл. Собеседника уведомит первое сообщение.
      room.notify_activity(only: current_user)
      render json: room_summary(room), status: :created
    end

    # POST /api/rooms/saved — персональная заметочная комната, аналог Telegram «Избранное».
    # Создаётся лениво, поэтому не плодит пустые комнаты всем зарегистрированным пользователям.
    def saved
      room = Room.saved_room_for(current_user)
      room.notify_activity(only: current_user)
      render json: room_summary(room), status: :created
    end

    # PATCH /api/rooms/:id { title:, avatar_url: } — переименовать группу и сменить её аватар.
    def update
      room = current_user.rooms.find(params[:id])
      return render json: {error: "not_a_group"}, status: :unprocessable_entity unless room.group?
      return render json: {error: "forbidden"}, status: :forbidden unless room.owned_by?(current_user)

      if params.key?(:title)
        title = params[:title].to_s.squish
        return render json: {error: "title_required"}, status: :unprocessable_entity if title.blank?
        return render json: {error: "title_too_long"}, status: :unprocessable_entity if title.length > MAX_ROOM_NAME_LENGTH

        room.name = title
      end
      avatar_upload = params[:avatar]
      avatar_info = UploadSafety.inspect!(avatar_upload, max_bytes: 5.megabytes) if avatar_upload.present?
      return render json: {error: "avatar_must_be_image"}, status: :unprocessable_entity if avatar_info && !avatar_info.content_type.start_with?("image/")

      # nil сбрасывает аватар обратно на стопку участников, поэтому именно key?, а не present?.
      if params.key?(:avatar_url)
        avatar_url = User.normalized_avatar_url(params[:avatar_url])
        return render json: {error: "invalid_avatar_url"}, status: :unprocessable_entity if params[:avatar_url].present? && avatar_url.nil?

        room.avatar_url = avatar_url
      end
      room.save!
      attach_avatar(room, avatar_upload, avatar_info) if avatar_upload.present?

      room.notify_activity
      render json: room_summary(room)
    rescue UploadSafety::UnsafeUpload => error
      render json: {error: error.message}, status: :unprocessable_entity
    end

    # DELETE /api/rooms/:id[?for_all=1] — убрать чат у себя или (создателю группы) снести его у всех.
    # Комнату, из которой ушёл последний участник, уносим целиком: переписку без читателей
    # никто уже не откроет, а её вложения продолжали бы занимать место в хранилище.
    def destroy
      room = current_user.rooms.find(params[:id])

      return destroy_for_all(room) if for_all? && room.group?
      return hide_direct_room(room) if room.direct?

      room.membership_for(current_user)&.destroy
      # Ушедшего в составе комнаты уже нет, поэтому notify_activity до него не дойдёт:
      # его собственные другие вкладки убирают группу из списка только по этому событию.
      Room.notify_rooms_changed(current_user)

      if room.reload.users.empty?
        room.destroy
      else
        transfer_ownership_if_needed(room)
        # Остальным чат остаётся — но состав участников у них поменялся.
        room.notify_activity
      end

      head :no_content
    end

    # POST /api/rooms/group { title:, members: [{ external_id:, name: }] }
    # Групповой чат: без dm_key, участники — создатель плюс переданные.
    # Имя группы приходит как title: параметр name уже занят под личность звонящего.
    def create_group
      title = params[:title].to_s.squish.presence
      return render json: {error: "title_required"}, status: :unprocessable_entity unless title
      return render json: {error: "title_too_long"}, status: :unprocessable_entity if title.length > MAX_ROOM_NAME_LENGTH
      return render json: {error: "too_many_members"}, status: :unprocessable_entity if Array(params[:members]).size > MAX_GROUP_MEMBERS

      members = upsert_members(params[:members]).uniq(&:id).reject { |member| member.id == current_user.id }
      return render json: {error: "too_many_members"}, status: :unprocessable_entity if members.size + 1 > MAX_GROUP_MEMBERS

      room = Room.create!(name: title, owner: current_user)
      room.add_member(current_user)
      members.each { |member| room.add_member(member) }

      room.reload.notify_activity
      render json: room_summary(room), status: :created
    end

    private

    def for_all?
      ActiveModel::Type::Boolean.new.cast(params[:for_all])
    end

    # Личку убираем только из своего списка, а участие сохраняем скрытым. Если удалить связь,
    # доставлять следующее сообщение собеседника станет некому: publish_message рассылает
    # участникам комнаты, и удалившего среди них уже нет. Скрытую личку вернёт reveal_to_members!.
    # Прочитанной помечаем сразу, иначе вместе с ней вернётся счётчик старых сообщений.
    def hide_direct_room(room)
      room.membership_for(current_user)&.update!(visible: false, last_read_at: Time.current)
      # Другие вкладки того же пользователя должны убрать чат из списка.
      room.notify_activity(only: current_user)
      # Личку, скрытую обоими участниками, показывать больше некому.
      room.destroy! if room.room_memberships.where(visible: true).none?

      head :no_content
    end

    def destroy_for_all(room)
      return render json: {error: "forbidden"}, status: :forbidden unless room.owned_by?(current_user)

      # Рассылку делаем после удаления: иначе клиент успевает повторно получить ещё живую группу
      # и держит её в кэше до следующего перехода между чатами.
      members = room.users.to_a
      room.destroy!
      members.each { |member| Room.notify_rooms_changed(member) }

      head :no_content
    end

    def find_or_create_dm(user_a, user_b)
      key = "dm:#{[user_a.id, user_b.id].sort.join('-')}"
      # Уникальный индекс dm_key страхует от дублей, а create_or_find_by переживает
      # два одновременных клика «Написать» без ActiveRecord::RecordNotUnique.
      room = Room.create_or_find_by!(dm_key: key)
      room.add_member(user_a)
      # Собеседнику диалог показывает только первое сообщение (reveal_to_members!). Само нажатие
      # «Написать» его список не трогает: иначе удалённая собеседником переписка возвращалась бы
      # к нему в список без единого нового сообщения — то есть кнопкой можно было бы навязываться.
      room.add_member(user_b, visible: false)
      room
    end

    def attach_avatar(room, upload, inspected)
      room.avatar.attach(
        io: upload.tempfile,
        filename: inspected.filename,
        content_type: inspected.content_type,
      )
    end

    # Если создатель выходит из группы, передаём управление самому давнему оставшемуся
    # участнику. Иначе owner_id ссылался бы на человека вне комнаты, и группа навсегда
    # теряла бы возможность менять состав, название и удаляться у всех.
    def transfer_ownership_if_needed(room)
      return unless room.group? && room.owned_by?(current_user)

      successor = room.room_memberships.includes(:user).order(:created_at, :id).first&.user
      room.update!(owner: successor) if successor
    end

    def room_summaries(rooms)
      room_ids = rooms.map(&:id)
      last_messages = last_messages_by_room(room_ids)
      unread_counts = unread_counts_by_room(room_ids)
      mention_counts = mention_counts_by_room(room_ids)
      memberships = memberships_by_room(room_ids)
      # Каналы остаются в выдаче: в них ходят по прямой ссылке и по вкладке в шапке группы,
      # и их непрочитанные входят в общий бейдж. Строкой левой панели они не становятся —
      # это решает клиент, потому что показывать их там нечем: у вкладки нет своей строки.
      channels_by_parent = rooms.select(&:channel?).group_by(&:parent_id)

      # Закреплённые сверху, внутри каждой группы — по свежести разговора. Ровно тот же порядок
      # держит sortRoomsByActivity на клиенте: WS-патч превью не переупорядочивает кэш, и если
      # правила разойдутся, список будет перепрыгивать после каждого перезапроса.
      ordered = rooms.sort_by do |room|
        [
          memberships[room.id]&.pinned? ? 0 : 1,
          -(last_messages[room.id]&.created_at || room.created_at).to_f
        ]
      end

      ordered.map do |room|
        room_summary(
          room,
          last: last_messages[room.id],
          unread_count: unread_counts.fetch(room.id, 0),
          mentions_count: mention_counts.fetch(room.id, 0),
          membership: memberships[room.id],
          channels: channel_summaries(channels_by_parent[room.id], unread_counts),
        )
      end
    end

    # Вкладки каналов: в шапке группы им нужны только имя и счётчик непрочитанных.
    def channel_summaries(channels, unread_counts)
      Array(channels).sort_by(&:id).map do |channel|
        {id: channel.id, name: channel.name, unread_count: unread_counts.fetch(channel.id, 0)}
      end
    end

    # id — монотонный первичный ключ сообщений, поэтому максимум среди видимых записей и есть
    # последнее сообщение комнаты. Сначала получаем только id, затем одной выборкой догружаем
    # автора и первое вложение для preview.
    def last_messages_by_room(room_ids)
      # Ответ discussion-треда не должен перебивать превью общего диалога: он остаётся внутри ветки.
      ids = Message.visible.timeline.where(room_id: room_ids).group(:room_id).maximum(:id).values
      return {} if ids.empty?

      Message.where(id: ids).includes(:user, :message_attachments).index_by(&:room_id)
    end

    def unread_counts_by_room(room_ids)
      return {} if room_ids.empty?

      unread_messages(room_ids).group(:room_id).count
    end

    # Непрочитанные упоминания считаются по тем же границам, что и непрочитанные вообще —
    # иначе бейдж «@» звал бы в чат, где упоминание уже прочитано.
    def mention_counts_by_room(room_ids)
      return {} if room_ids.empty?

      unread_messages(room_ids)
        .where(id: MessageMention.where(user_id: current_user.id).select(:message_id))
        .group(:room_id)
        .count
    end

    def unread_messages(room_ids)
      Message
        .visible
        .joins(room: :room_memberships)
        .where(room_id: room_ids, room_memberships: {user_id: current_user.id})
        .where.not(user_id: current_user.id)
        .where.not(user_id: UserBlock.where(blocker_id: current_user.id).select(:blocked_id))
        .where("room_memberships.last_read_at IS NULL OR messages.created_at > room_memberships.last_read_at")
    end

    def memberships_by_room(room_ids)
      return {} if room_ids.empty?

      RoomMembership.where(room_id: room_ids, user_id: current_user.id).index_by(&:room_id)
    end

    def room_summary(room, last: :load, unread_count: :load, mentions_count: :load, membership: :load, channels: :load)
      last = room.messages.visible.timeline.includes(:user, :message_attachments).order(id: :desc).first if last == :load
      unread_count = room.unread_count_for(current_user) if unread_count == :load
      mentions_count = room.mention_unread_count_for(current_user) if mentions_count == :load
      membership = room.membership_for(current_user) if membership == :load
      channels = room.channels.map { |channel| {id: channel.id, name: channel.name, unread_count: channel.unread_count_for(current_user)} } if channels == :load

      {
        id: room.id,
        name: room.display_name_for(current_user),
        # Момент создания — запасная отметка порядка: пустой диалог, только что открытый
        # кнопкой «Написать», должен стоять сверху, а не в конце списка.
        created_at: room.created_at.iso8601,
        is_group: room.group?,
        is_saved: room.saved?,
        # Аватар группы задаёт её создатель; без него фронт рисует стопку участников.
        avatar_url: room.avatar_image_url,
        owner_external_id: room.owner&.external_id,
        block_state: room.block_state_for(current_user),
        members: room.users.map { |user| member_json(user) },
        unread_count: unread_count,
        # Непрочитанные упоминания: бейдж «@» показывается даже у приглушённого чата.
        mentions_count: mentions_count,
        # Личные настройки чата: у каждого участника свои.
        muted: membership&.muted? || false,
        pinned: membership&.pinned? || false,
        marked_unread: membership&.marked_unread? || false,
        # Архивный чат уходит в отдельную секцию списка, но продолжает считать непрочитанные.
        archived: membership&.archived? || false,
        theme: membership&.theme_name || RoomMembership::DEFAULT_THEME,
        # Исчезающие сообщения — настройка комнаты, общая для всех её участников.
        ttl_seconds: room.ttl_seconds,
        # Канал показывается вкладкой внутри своей группы, а не отдельной строкой списка.
        parent_id: room.parent_id,
        is_channel: room.channel?,
        channels: channels,
        last_message: last && {
          # Превью, а не тело: у сообщения с вложением текста может не быть вовсе.
          body: last.hidden_from?(current_user) ? "Сообщение скрыто" : last.preview_text,
          author: last.hidden_from?(current_user) ? "" : last.user.name,
          created_at: last.created_at.iso8601
        }
      }
    end
  end
end
