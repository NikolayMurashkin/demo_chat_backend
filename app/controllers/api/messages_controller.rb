# frozen_string_literal: true

module Api
  class MessagesController < BaseController
    before_action :throttle_upload, only: :create
    before_action :throttle_forward, only: :forward
    PAGE_SIZE = 30
    # Окно вокруг найденного сообщения: половина страницы вверх, половина вниз.
    AROUND_HALF_SIZE = PAGE_SIZE / 2
    SEARCH_LIMIT = 50
    MAX_SEARCH_QUERY_LENGTH = 200
    # Вложения хранятся в Postgres, поэтому лимит сдерживает и память запроса, и рост БД.
    MAX_ATTACHMENT_BYTES = 10.megabytes
    MAX_ATTACHMENTS = 5
    MAX_UPLOAD_BYTES = 25.megabytes
    MAX_BODY_LENGTH = 10_000
    MAX_FORWARD_MESSAGES = 20
    MAX_FORWARD_ROOMS = 20
    # Один запрос пересылки создаёт messages × rooms сообщений. Без отдельного потолка общий
    # лимит HTTP пропускал бы 400 записей за запрос — рассылка, а не пересылка.
    MAX_FORWARD_COPIES = 60
    MAX_FORWARD_COMMENT_LENGTH = 2_000
    MAX_WAVEFORM_SAMPLES = 300
    # Цитата фрагмента: в пузыре она занимает пару строк, длинное выделение обрезаем.
    MAX_QUOTE_LENGTH = 300

    # GET /api/rooms/:room_id/messages?before=<id>&after=<id>&around=<id>
    # История комнаты курсорами в обе стороны: вверх — при прокрутке к началу,
    # вниз — после прыжка к найденному сообщению (around отдаёт окно вокруг него).
    def index
      room = current_user.rooms.find(params[:room_id])
      # Просроченные исчезающие убираем до выборки: очередь джоб живёт в памяти процесса и
      # не переживает его перезапуск, а сообщение с вышедшим сроком показывать нельзя никогда.
      room.sweep_expired_messages!
      messages = load_page(room)

      render json: {
        messages: messages.map { |message| message.as_chat_json(viewer: current_user) },
        # Отдельным списком: закреплённое может быть старше загруженной страницы истории.
        pinned: pinned_messages(room).reject { |message| message.hidden_from?(current_user) }.map { |message| message.as_chat_json(viewer: current_user) },
        next_before: cursor_before(room, messages),
        next_after: cursor_after(room, messages),
        # Когда собеседник последний раз читал — для галочек «прочитано» у своих сообщений.
        peer_last_read_at: room.peer_last_read_at_for(current_user)&.iso8601,
        # Своя отметка прочтения на момент открытия — по ней рисуется разделитель «Новые сообщения».
        my_last_read_at: room.membership_for(current_user)&.last_read_at&.iso8601
      }
    end

    # GET /api/rooms/:room_id/messages/:id/thread
    # Корневое сообщение остаётся видимым для контекста, а ответы живут только в этой выдаче.
    def thread
      room = current_user.rooms.find(params[:room_id])
      root = room.messages.visible.timeline.with_chat_payload.find(params[:id])
      replies = root.thread_replies.visible.with_chat_payload.order(:id).limit(PAGE_SIZE)

      render json: {
        root: root.as_chat_json(viewer: current_user),
        messages: replies.map { |message| message.as_chat_json(viewer: current_user) },
        next_before: nil
      }
    end

    # POST /api/rooms/:room_id/messages (multipart)
    # Отправка с вложениями: по WS бинарь не гонится, поэтому файлы едут HTTP-запросом,
    # а разослано сообщение будет тем же broadcast'ом, что и текстовое.
    def create
      room = current_user.rooms.find(params[:room_id])
      return render_chat_blocked if room.direct_chat_blocked_for?(current_user)

      files = Array(params[:files])
      body = body_param
      thread_root = discussion_root(room, params[:thread_root_id])

      return render json: {error: "empty_message"}, status: :unprocessable_entity if files.empty? && body.blank?
      return render json: {error: "invalid_thread_root"}, status: :unprocessable_entity if params[:thread_root_id].present? && thread_root.nil?
      return render json: {error: "too_many_attachments"}, status: :unprocessable_entity if files.size > MAX_ATTACHMENTS
      return render json: {error: "message_too_long"}, status: :unprocessable_entity if body.to_s.length > MAX_BODY_LENGTH

      inspected_files = files.map { |file| UploadSafety.inspect!(file, max_bytes: MAX_ATTACHMENT_BYTES) }
      upload_bytes = inspected_files.sum(&:byte_size)
      return render json: {error: "upload_too_large"}, status: :payload_too_large if upload_bytes > MAX_UPLOAD_BYTES

      # Не оставляем в истории сообщение без части вложений, если Active Storage или БД
      # отказали посреди загрузки. Broadcast уйдёт только после успешного коммита.
      message = ChatStorageQuota.reserve_upload!(user: current_user, room: room, byte_size: upload_bytes) do
        Message.transaction do
          created = room.messages.create!(
            user: current_user,
            body: body,
            reply_to: room_message(room, params[:reply_to_id]),
            thread_root: thread_root,
            silent: silent?,
            view_once: view_once?,
            quote_text: quote_text_param,
          )
          files.each_with_index { |file, index| attach_file(created, file, inspected_files[index], attachment_meta(index)) }
          created
        end
      end

      broadcast(room, message.reload)
      message.enqueue_link_preview
      render json: message.as_chat_json(viewer: current_user), status: :created
    rescue UploadSafety::UnsafeUpload => error
      status = error.message == "file_too_large" ? :payload_too_large : :unprocessable_entity
      render json: {error: error.message}, status: status
    rescue ChatStorageQuota::Exceeded => error
      render json: {error: error.message}, status: :insufficient_storage
    end

    # POST /api/messages/forward { message_ids: [], room_ids: [] }
    # Пересылка кросс-комнатная, поэтому REST, а не WS-экшен канала комнаты:
    # копии создаются в целевых комнатах и рассылаются их подписчикам.
    def forward
      sources = forward_sources
      targets = forward_targets
      comment = forward_comment

      return render json: {error: "messages_required"}, status: :unprocessable_entity if sources.empty?
      return render json: {error: "rooms_required"}, status: :unprocessable_entity if targets.empty?
      if sources.size * targets.size > MAX_FORWARD_COPIES
        return render json: {error: "too_many_forward_copies"}, status: :unprocessable_entity
      end
      return render_chat_blocked if targets.any? { |room| room.direct_chat_blocked_for?(current_user) }
      return render json: {error: "forward_comment_too_long"}, status: :unprocessable_entity if params[:comment].to_s.length > MAX_FORWARD_COMMENT_LENGTH

      created = targets.flat_map { |room| forward_to_room(room, sources, comment) }
      render json: {forwarded_count: created.size}, status: :created
    end

    # POST /api/messages/:id/save — копирует доступное пользователю сообщение в «Избранное».
    # Вложение переиспользует тот же blob: важное сообщение не удваивает занятую квоту.
    def save
      source = Message.visible.where(id: params[:id], room_id: current_user.rooms.select(:id)).with_chat_payload.first
      return render json: {error: "not_found"}, status: :not_found unless source
      return render json: {error: "not_found"}, status: :not_found if source.hidden_from?(current_user)

      room = Room.saved_room_for(current_user)
      saved = Message.transaction { copy_message(source, room) }

      room.broadcast_message(saved.reload)
      room.notify_activity(only: current_user)
      render json: {saved_room_id: room.id}, status: :created
    end

    # GET /api/rooms/:room_id/messages/:id/readers — кто уже прочитал сообщение.
    # Отметка прочтения у каждого участника своя, и по ней же считаются галочки: список имён —
    # это та же информация, только развёрнутая.
    def readers
      room = current_user.rooms.find(params[:room_id])
      message = room.messages.visible.find(params[:id])

      render json: {
        readers: room.readers_of(message).map do |membership|
          {
            external_id: membership.user.external_id,
            name: membership.user.name,
            avatar_url: membership.user.avatar_url,
            read_at: membership.last_read_at.iso8601
          }
        end,
        # Сколько всего человек могло прочитать: автора среди них нет.
        recipients_count: room.room_memberships.where.not(user_id: message.user_id).count
      }
    end

    # POST /api/messages/:id/star — личная отметка «важное».
    def star
      message = accessible_message
      return render json: {error: "not_found"}, status: :not_found unless message

      StarredMessage.create!(user: current_user, message: message)
      render json: {message_id: message.id, starred: true}, status: :created
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Повторная отметка — не ошибка: две вкладки могли нажать кнопку одновременно.
      render json: {message_id: message.id, starred: true}, status: :created
    end

    # DELETE /api/messages/:id/star
    def unstar
      message = accessible_message
      return render json: {error: "not_found"}, status: :not_found unless message

      StarredMessage.where(user: current_user, message: message).destroy_all
      render json: {message_id: message.id, starred: false}
    end

    # POST /api/messages/:id/view — раскрывает одноразовое сообщение ровно один раз.
    # Ответ приходит только запросившему: содержимое не уходит ни в broadcast, ни в историю,
    # иначе «посмотреть один раз» осталось бы только оформлением.
    def view
      message = accessible_message
      return render json: {error: "not_found"}, status: :not_found unless message
      return render json: {error: "not_view_once"}, status: :unprocessable_entity unless message.view_once?
      return render json: {error: "already_viewed"}, status: :gone if message.viewed_by?(current_user)

      message.mark_viewed!(current_user)
      # Автору сразу показываем, что сообщение открыли: у него в пузыре стоит счётчик просмотров.
      author_frame = message.reload.as_chat_json(viewer: message.user)
      ChatChannel.broadcast_to([message.room, message.user], author_frame)

      render json: message.revealed_chat_json(current_user)
    end

    # GET /api/rooms/:room_id/messages/search?q=<текст>
    # Поиск внутри диалога: свежие сверху, клик по результату прыгает в тред через around.
    # Синтаксис фильтров (from:, has:) тот же, что и в глобальном поиске.
    def search
      room = current_user.rooms.find(params[:room_id])
      raw = params[:q].to_s.strip
      return render json: {error: "query_too_long"}, status: :unprocessable_entity if raw.length > MAX_SEARCH_QUERY_LENGTH

      query = MessageSearchQuery.new(raw)
      return render json: {messages: []} if query.blank?

      found = query.apply(room.messages.visible, viewer: current_user)
                   .with_chat_payload.order(id: :desc).limit(SEARCH_LIMIT)
      found = found.reject { |message| message.hidden_from?(current_user) }
      render json: {messages: found.map { |message| message.as_chat_json(viewer: current_user) }}
    end

    private

    def throttle_upload
      ip_allowed = ChatRateLimiter.allow?("upload_ip:#{request.remote_ip}", limit: 6, period: 60)
      user_allowed = ChatRateLimiter.allow?("upload_user:#{current_user.id}", limit: 4, period: 60)
      return if ip_allowed && user_allowed

      render json: {error: "rate_limited"}, status: :too_many_requests
    end

    # Пересылка — единственная ручка, где один запрос порождает десятки сообщений сразу
    # в нескольких чужих чатах. Свой лимит держит её заметно ниже общего HTTP-потолка.
    def throttle_forward
      return if ChatRateLimiter.allow?("forward:#{current_user.id}", limit: 10, period: 60)

      render json: {error: "rate_limited"}, status: :too_many_requests
    end

    def render_chat_blocked
      render json: {error: "direct_chat_blocked"}, status: :forbidden
    end

    def body_param
      Message.normalized_body(params[:body])
    end

    # Сообщение, доступное текущему пользователю: выбираем среди сообщений его же комнат.
    def accessible_message
      message = Message.visible.where(id: params[:id], room_id: current_user.rooms.select(:id)).with_chat_payload.first

      message unless message.nil? || message.hidden_from?(current_user)
    end

    def silent?
      ActiveModel::Type::Boolean.new.cast(params[:silent]) || false
    end

    def view_once?
      ActiveModel::Type::Boolean.new.cast(params[:view_once]) || false
    end

    # Цитата фрагмента — простой текст выделения, а не разметка: в пузыре она рисуется
    # отдельной строкой, и HTML в ней был бы ещё одним путём для чужих тегов.
    def quote_text_param
      text = Message.plain_text_from_html(params[:quote_text].to_s).delete("<>")

      text.presence&.truncate(MAX_QUOTE_LENGTH)
    end

    # Метаданные вложений едут параллельным массивом: у голосового это длительность и пики,
    # у остальных — размеры картинки/видео, посчитанные на фронте до отправки.
    def attachment_meta(index)
      meta = Array(params[:attachments_meta])[index]

      return {} if meta.blank?

      parsed = meta.is_a?(String) ? JSON.parse(meta) : (meta.is_a?(Hash) ? meta : meta.to_unsafe_h)
      return {} unless parsed.is_a?(Hash)

      {
        "voice" => ActiveModel::Type::Boolean.new.cast(parsed["voice"]),
        "duration_ms" => bounded_integer(parsed["duration_ms"], 0, 7.days.in_milliseconds),
        "width" => bounded_integer(parsed["width"], 1, 10_000),
        "height" => bounded_integer(parsed["height"], 1, 10_000),
        "waveform" => safe_waveform(parsed["waveform"])
      }.compact
    rescue JSON::ParserError, NoMethodError, TypeError
      {}
    end

    def attach_file(message, file, inspected, meta)
      kind = MessageAttachment.kind_for(inspected.content_type, voice: meta["voice"])

      attachment = message.message_attachments.create!(
        kind: kind,
        filename: inspected.filename,
        content_type: inspected.content_type,
        byte_size: inspected.byte_size,
        duration_ms: meta["duration_ms"],
        width: meta["width"],
        height: meta["height"],
        waveform: meta["waveform"] && Array(meta["waveform"]).to_json,
      )
      attachment.file.attach(
        io: file.tempfile,
        filename: inspected.filename,
        content_type: inspected.content_type,
      )
      attachment
    end

    def bounded_integer(value, minimum, maximum)
      number = Integer(value, exception: false)
      number if number && number.between?(minimum, maximum)
    end

    def safe_waveform(value)
      samples = Array(value)
      return if samples.empty? || samples.size > MAX_WAVEFORM_SAMPLES
      return unless samples.all? { |sample| sample.is_a?(Numeric) && sample.finite? && sample.between?(0, 1) }

      samples
    end

    def load_page(room)
      scope = room.messages.visible.timeline.with_chat_payload
      around = cursor(params[:around])
      after = cursor(params[:after])
      before = cursor(params[:before])

      return around_page(scope, around) if around

      return scope.where("messages.id > ?", after).order(id: :asc).limit(PAGE_SIZE).to_a if after

      scope = scope.where("messages.id < ?", before) if before
      # Клиенту — в хронологическом порядке (старые -> новые).
      scope.order(id: :desc).limit(PAGE_SIZE).to_a.reverse
    end

    # Курсор — это id сообщения. Постгресу нельзя отдать сюда произвольную строку из query:
    # сравнение bigint со «строкой» падает ошибкой типа, то есть 500 вместо пустой страницы.
    def cursor(value)
      return if value.blank?

      id = Integer(value, exception: false)
      id if id&.positive?
    end

    # Окно вокруг сообщения: само сообщение с предысторией плюс то, что за ним.
    def around_page(scope, message_id)
      older = scope.where("messages.id <= ?", message_id).order(id: :desc).limit(AROUND_HALF_SIZE).to_a.reverse
      newer = scope.where("messages.id > ?", message_id).order(id: :asc).limit(AROUND_HALF_SIZE).to_a

      older + newer
    end

    # Курсоры отдаём только когда за краем выдачи действительно что-то есть —
    # иначе тред бесконечно дёргал бы подгрузку на первом же сообщении комнаты.
    def cursor_before(room, messages)
      oldest = messages.first
      return if oldest.nil?

      oldest.id if room.messages.visible.where("messages.id < ?", oldest.id).exists?
    end

    def cursor_after(room, messages)
      newest = messages.last
      return if newest.nil?

      newest.id if room.messages.visible.where("messages.id > ?", newest.id).exists?
    end

    def pinned_messages(room)
      room.messages.visible.timeline.pinned.with_chat_payload
    end

    def room_message(room, message_id)
      return if message_id.blank?

      room.messages.find_by(id: message_id)
    end

    def discussion_root(room, message_id)
      return if message_id.blank?

      room.messages.visible.timeline.find_by(id: message_id)
    end

    # Пересылать можно только то, что видно самому: выбираем среди сообщений своих комнат.
    def forward_sources
      ids = Array(params[:message_ids]).map(&:to_i)
      return [] if ids.empty? || ids.size > MAX_FORWARD_MESSAGES

      Message.visible.where(id: ids, room_id: current_user.rooms.select(:id)).with_chat_payload.order(:id).to_a
             .reject { |message| message.hidden_from?(current_user) }
    end

    def forward_targets
      ids = Array(params[:room_ids]).map(&:to_i)
      return [] if ids.empty? || ids.size > MAX_FORWARD_ROOMS

      current_user.rooms.where(id: ids).to_a
    end

    def forward_comment
      Message.normalized_body(params[:comment])
    end

    def forward_to_room(room, sources, comment)
      created, forwarded = Message.transaction do
        comment_message = room.messages.create!(user: current_user, body: comment) if comment

        forwarded = sources.map { |source| copy_message(source, room) }

        [[comment_message, *forwarded].compact, forwarded]
      end

      # Сами сообщения нужны в realtime все, но обновление списка и browser-notification — один
      # раз на комнату. Иначе пересылка 20 сообщений превращалась в 20 одинаковых уведомлений.
      created.each { |message| room.broadcast_message(message.reload) }
      broadcast_activity(room, created.last) if created.any?
      forwarded
    end

    def copy_message(source, room)
      copy = room.messages.create!(
        user: current_user,
        body: source.body,
        # Пересылка пересланного сохраняет первоисточник, а не предыдущего отправителя.
        forwarded_from_name: source.forwarded_from_name.presence || source.user.name,
        forwarded_from_external_id: source.forwarded_from_external_id.presence || source.user.external_id,
      )
      source.message_attachments.each { |attachment| copy_attachment(attachment, copy) }
      copy
    end

    # Блоб переиспользуем: пересылка не должна плодить копии файла в хранилище.
    def copy_attachment(attachment, message)
      copy = message.message_attachments.create!(
        attachment.slice(:kind, :filename, :content_type, :byte_size, :duration_ms, :width, :height, :waveform),
      )
      copy.file.attach(attachment.file.blob)
      copy
    end

    def broadcast(room, message)
      room.publish_message(message)
    end

    def broadcast_activity(room, message)
      # Участникам обновляем список чатов и бейджи, даже если этот чат у них не открыт.
      room.reveal_to_members!
      room.notify_activity(except: current_user)
      room.notify_incoming(message)
    end
  end
end
