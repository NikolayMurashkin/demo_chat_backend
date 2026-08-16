# frozen_string_literal: true

class ChatChannel < ApplicationCable::Channel
  MAX_BODY_LENGTH = 10_000
  CLIENT_MESSAGE_ID_PATTERN = /\A[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}\z/i
  # Сложные Unicode-emoji (семьи, флаги, тоны кожи) состоят из нескольких codepoint'ов.
  # 64 покрывает такие последовательности, не оставляя канал без ограничения размера.
  MAX_EMOJI_LENGTH = 64
  # Цитата фрагмента: в пузыре она занимает пару строк, длинное выделение обрезаем.
  MAX_QUOTE_LENGTH = 300
  # Чем занят собеседник прямо сейчас. Всё неизвестное считаем набором текста.
  ACTIVITY_KINDS = %w[typing attachment voice].freeze
  # Клиент подписывается с { channel: "ChatChannel", room_id: 1 }.
  # По частоте подписка не ограничивается — см. тот же разбор в UserChannel. Человек с пятью
  # открытыми чатами переподписывает пять каналов на каждый реконнект, и прежние 30 в минуту
  # выедались обычной работой, а не флудом. Отказ при этом терминален: комната оставалась
  # мёртвой до перезагрузки страницы.
  def subscribed
    # Только комнаты, где текущий юзер — участник (иначе reject_subscription).
    room = joined_room
    return reject unless room

    # Сообщения персонализированы: заблокировавший участник группы получает безопасную
    # заглушку вместо контента автора, поэтому общий room-stream здесь использовать нельзя.
    stream_for [room, current_user]
  end

  def unsubscribed
    stop_all_streams
  end

  # Клиент прислал { action: "send_message", body: "...", reply_to_id: 12, thread_root_id: 7 }.
  # Автор — current_user из Connection (не из данных клиента).
  # Сначала СОХРАНЯЕМ, потом рассылаем сохранённое — у всех один объект с id/created_at.
  def send_message(data)
    room = joined_room
    return if room.nil?

    # Короткие реплики на демо часто отправляют серией. Старый лимит 20/мин молча
    # отбрасывал хвост серии, из-за чего у отправителя оставался только локальный пузырь.
    return reject_message(room, data, "rate_limited") unless allow_action?(:message)
    return reject_message(room, data, "blocked") if room.direct_chat_blocked_for?(current_user)

    body = normalized_body(data["body"])
    return reject_message(room, data, "empty") if body.nil?
    return reject_message(room, data, "too_long") if body.length > MAX_BODY_LENGTH

    thread_root = discussion_root(room, data["thread_root_id"])
    return reject_message(room, data, "invalid_thread_root") if data["thread_root_id"].present? && thread_root.nil?

    message = room.messages.create!(
      user: current_user,
      body: body,
      reply_to: find_room_message(room, data["reply_to_id"]),
      thread_root: thread_root,
      # Тихая отправка: сообщение доставляется как обычное, молчат только звук и системное окно.
      silent: data["silent"] == true,
      # Одноразовое: получателю содержимое отдаётся ровно один раз, по отдельному запросу.
      view_once: data["view_once"] == true,
      quote_text: quote_text(data),
    )
    room.publish_message(message, client_message_id: client_message_id(data))
    message.enqueue_link_preview
  end

  # Клиент прислал { action: "mark_read" } — юзер открыл/дочитал комнату.
  # Двигаем его last_read_at и рассылаем событие read, чтобы у автора галочки стали «прочитано».
  def mark_read
    room = joined_room
    return if room.nil?
    # Отметка о прочтении уходит на каждое входящее и на возвращение во вкладку, поэтому
    # её потолок не ниже потолка отправки: иначе в оживлённой группе бейдж переставал
    # обнуляться раньше, чем собеседники переставали писать.
    return unless allow_action?(:read)

    # Ручная пометка «непрочитано» держится ровно до открытия чата — как в телеге.
    # Сама отметка живёт в модели: тем же переходом пользуется REST-действие из списка чатов.
    room.mark_read_for(current_user)
  end

  # Клиент прислал { action: "typing", kind: "voice", active: false } — рассылаем, чем занят
  # собеседник (эфемерно, без записи в БД). Себя клиент отфильтровывает по external_id.
  # active: false — явный конец активности: без него индикатор гас бы только по таймауту.
  #
  # Аргумент обязателен, и это не стилистика: ActionCable передаёт data только в метод с
  # arity == 1. Со значением по умолчанию arity равен -1, метод вызывался вовсе без аргумента,
  # и data всегда оставалась пустой — kind терялся, а «перестал печатать» не доезжал никогда.
  def typing(data)
    room = joined_room
    return if room.nil?
    return unless allow_action?(:typing)
    return if room.direct_chat_blocked_for?(current_user)

    kind = data["kind"].to_s
    kind = "typing" unless ACTIVITY_KINDS.include?(kind)

    # from: — заблокировавший участник группы не должен видеть даже «печатает…» от того,
    # чьи сообщения ему уже не показываются.
    room.broadcast_chat_event({
      type: "typing",
      room_id: room.id,
      external_id: current_user.external_id,
      name: current_user.name,
      kind: kind,
      active: data["active"] != false
    }, from: current_user)
  end

  # Клиент прислал { action: "toggle_reaction", message_id: 12, emoji: "👍" }.
  # Повторный клик по своей реакции снимает её — как в мессенджерах.
  def toggle_reaction(data)
    room = joined_room
    return if room.nil?
    return unless allow_action?(:reaction)
    return if room.direct_chat_blocked_for?(current_user)

    message = find_room_message(room, data["message_id"])
    emoji = data["emoji"].to_s.strip.presence
    return if message.nil? || emoji.nil?
    return if emoji.length > MAX_EMOJI_LENGTH || emoji.match?(/[[:cntrl:]]/)

    return if message.deleted?
    # Реагировать на скрытое сообщение нельзя: его содержимого мы не показывали.
    return if message.hidden_from?(current_user)

    reaction = message.message_reactions.find_by(user: current_user, emoji: emoji)
    reaction ? reaction.destroy! : message.message_reactions.create!(user: current_user, emoji: emoji)

    # Рассылаем сообщение целиком: клиент апсертит его по id и не разбирает отдельный тип события.
    room.broadcast_message(message.reload)
  end

  # Клиент прислал { action: "toggle_pin", message_id: 12 }.
  # Закреплять и откреплять может любой участник комнаты — и в группе, и в личке.
  def toggle_pin(data)
    room = joined_room
    return if room.nil?
    return unless allow_action?(:pin)
    return if room.direct_chat_blocked_for?(current_user)

    message = find_room_message(room, data["message_id"])
    return if message.nil? || message.deleted? || message.hidden_from?(current_user)

    message.update!(pinned_at: message.pinned? ? nil : Time.current)
    room.broadcast_message(message)
  end

  # Клиент прислал { action: "edit_message", message_id: 12, body: "..." }.
  def edit_message(data)
    room = joined_room
    return if room.nil?
    return unless allow_action?(:edit)
    return if room.direct_chat_blocked_for?(current_user)

    message = own_message(room, data["message_id"])
    body = normalized_body(data["body"])
    return if message.nil? || body.nil? || body.length > MAX_BODY_LENGTH

    message.update!(body: body, edited_at: Time.current)
    room.broadcast_message(message)
    message.enqueue_link_preview
  end

  # Клиент прислал { action: "delete_message", message_id: 12 }.
  def delete_message(data)
    room = joined_room
    return if room.nil?
    return unless allow_action?(:delete)

    # Удалять своё разрешено и в заблокированном диалоге: это не общение с собеседником,
    # а уборка за собой, и запрет оставлял бы человека без контроля над своими сообщениями.
    message = own_message(room, data["message_id"])
    return if message.nil?

    message.soft_delete!
    room.broadcast_message(message)
  end

  private

  # Членство проверяется на КАЖДОЕ действие, а не только при подписке. Открытый сокет живёт
  # долго: за это время участника могут исключить из группы, он может выйти сам с другой
  # вкладки или группу удалят у всех. Комната, запомненная при subscribed, позволяла бы ему
  # писать дальше — то есть отправлять сообщения туда, где его уже нет.
  def joined_room
    current_user.rooms.find_by(id: params[:room_id])
  end

  # Отправка по WS не имеет ответа: молча отброшенное сообщение оставляло автора с локальным
  # пузырём, который лишь через 15 секунд превращался в «Не отправлено». Возвращаем причину
  # сразу и только автору — его поток персональный.
  def reject_message(room, data, reason)
    ChatChannel.broadcast_to([room, current_user], {
      type: "message_rejected",
      room_id: room.id,
      client_message_id: client_message_id(data),
      reason: reason
    })
    nil
  end

  # Править и удалять можно только свои сообщения.
  def own_message(room, message_id)
    message = find_room_message(room, message_id)
    message if message&.user_id == current_user.id && !message.deleted?
  end

  # Цитировать и реагировать можно только на сообщения этой же комнаты.
  def find_room_message(room, message_id)
    return if message_id.blank?

    room.messages.find_by(id: message_id)
  end

  def discussion_root(room, message_id)
    return if message_id.blank?

    room.messages.visible.timeline.find_by(id: message_id)
  end

  def normalized_body(value)
    Message.normalized_body(value)
  end

  # Цитата фрагмента — простой текст выделения, а не разметка: в пузыре она рисуется
  # отдельной строкой, и HTML в ней был бы ещё одним путём для чужих тегов.
  def quote_text(data)
    text = Message.plain_text_from_html(data["quote_text"].to_s).delete("<>")

    text.presence&.truncate(MAX_QUOTE_LENGTH)
  end

  # Не сохраняем id в БД: он нужен лишь автору, чтобы сопоставить broadcast с локальной отправкой.
  def client_message_id(data)
    value = data["client_message_id"].to_s
    value if value.match?(CLIENT_MESSAGE_ID_PATTERN)
  end

  # Ключ — по человеку, без IP. IP в ключе делал бюджет общим для всех, кто сидит за одним
  # адресом: пять человек с одного Wi-Fi (или из одного VPN-выхода) душили друг друга, и чем
  # активнее шло демо, тем хуже работал чат. Перебор личностей ограничивает Connection, а не
  # каждое действие в отдельности.
  def allow_action?(name)
    ChatRateLimiter.allow?("ws:#{name}:#{current_user.id}", **ChatLimits.rate(name))
  end
end
