# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :room
  belongs_to :user
  # Ответ на сообщение: цитируемое может быть удалено — связь опциональная.
  belongs_to :reply_to, class_name: "Message", optional: true
  has_many :replies, class_name: "Message", foreign_key: :reply_to_id, dependent: :nullify, inverse_of: :reply_to
  # Discussion — отдельная ветка у сообщения. Обычный reply_to остаётся лёгкой цитатой в общей ленте.
  belongs_to :thread_root, class_name: "Message", optional: true
  has_many :thread_replies, class_name: "Message", foreign_key: :thread_root_id, dependent: :nullify, inverse_of: :thread_root
  has_many :message_reactions, dependent: :destroy
  has_many :message_attachments, -> { order(:id) }, dependent: :destroy, inverse_of: :message
  has_many :message_mentions, dependent: :destroy
  has_many :mentioned_users, through: :message_mentions, source: :user
  # Кто уже открыл одноразовое сообщение: содержимое достаётся каждому получателю однажды.
  has_many :message_views, dependent: :destroy
  # Личные отметки «важное» разных участников — сообщение о них ничего не решает, только несёт.
  has_many :starred_messages, dependent: :destroy
  # Опрос — часть сообщения: приходит тем же broadcast'ом и живёт ровно столько же.
  has_one :poll, dependent: :destroy

  before_save :sanitize_body, :sync_plain_body
  # Срок жизни проставляется на записи, а не при отправке: сообщение создаётся из канала,
  # из HTTP-контроллера, из пересылки и из отложенной доставки — правило должно быть одно.
  before_create :apply_room_expiry
  # Только после записи: разбор упоминаний идёт по уже очищенному телу и требует id сообщения.
  after_save :sync_mentions, if: :saved_change_to_body?
  after_create_commit :schedule_expiry

  scope :visible, -> { where(deleted_at: nil) }
  scope :timeline, -> { where(thread_root_id: nil) }
  # Закреплённые — в порядке закрепления: панель показывает последнее закреплённое.
  scope :pinned, -> { where.not(pinned_at: nil).order(:pinned_at) }
  # Поиск идёт по текстовой копии тела: в HTML нашлись бы имена тегов, а разорванный
  # разметкой текст — нет. Регистр гасим сами: LIKE в SQLite нечувствителен только к ASCII.
  scope :matching, lambda { |query|
    where("LOWER(messages.plain_body) LIKE ?", "%#{sanitize_sql_like(query.to_s.downcase)}%")
  }
  # Фильтр has:link. Ссылку и оформляют инструментом композера (href), и просто набирают
  # текстом — ищем оба варианта. LIKE вместо регулярного выражения: одна и та же выборка
  # должна работать и на SQLite (dev/test), и на PostgreSQL (production).
  scope :with_link, lambda {
    where(
      "messages.body LIKE ? OR messages.plain_body LIKE ? OR messages.plain_body LIKE ?",
      "%href=%", "%http://%", "%https://%"
    )
  }
  # Фильтр has:file. Подзапросом, а не join'ом: у сообщения бывает несколько вложений,
  # и join размножил бы его в выдаче.
  scope :with_attachment, -> { where(id: MessageAttachment.select(:message_id)) }
  scope :mentioning, ->(user) { where(id: MessageMention.where(user_id: user.id).select(:message_id)) }
  # Исчезающие, чей срок уже вышел. Джоба удаляет их в реальном времени, а этот scope
  # подметает то, что она могла не выполнить: процесс демо перезапускается вместе с очередью.
  scope :expired, -> { visible.where.not(expires_at: nil).where(expires_at: ..Time.current) }
  # Предзагрузка всего, что попадает в as_chat_json.
  # message_mentions здесь ради mentions_me: без предзагрузки каждая страница истории делала бы
  # по запросу на сообщение только для того, чтобы понять, упомянули ли в нём читателя.
  scope :with_chat_payload, lambda {
    includes(
      :user, :message_attachments, :message_mentions, :message_views, :starred_messages,
      {reply_to: :user}, {message_reactions: :user}, {poll: [:poll_options, :poll_votes]}
    )
  }

  DELETED_BODY = "".freeze
  LINK_PATTERN = %r{https?://[^\s<>"')]+}i
  ALLOWED_HTML_TAGS = %w[a p br hr strong b em i u s ul ol li blockquote code pre span h1 h2 h3 h4 h5 h6].freeze
  # data-mention несёт external_id упомянутого. Атрибут только для чтения: строки упоминаний
  # заводятся не по нему напрямую, а после сверки со списком участников комнаты.
  ALLOWED_HTML_ATTRIBUTES = %w[href data-mention].freeze
  # Сколько упоминаний одного сообщения вообще разбираем: «@все» списком из тысячи span'ов
  # не должно превращаться в тысячу строк и тысячу уведомлений.
  MAX_MENTIONS = 50

  class << self
    # Контроллеры и WS используют один путь нормализации: активный HTML не попадёт в базу,
    # а разметка без видимого текста не создаст в диалоге пустой пузырь.
    def normalized_body(value)
      body = sanitized_body(value)
      body if plain_text_from_html(body).present?
    end

    def sanitized_body(value)
      ActionController::Base.helpers.sanitize(
        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: ""),
        tags: ALLOWED_HTML_TAGS,
        attributes: ALLOWED_HTML_ATTRIBUTES,
      )
    end

    def plain_text_from_html(value)
      text = value.to_s.gsub(%r{</(p|div|li|ul|ol|br)>}i, " ").gsub(/<[^>]*>/, "")
      CGI.unescapeHTML(text).gsub(/&nbsp;/i, " ").tr("\u00A0", " ").squish
    end
  end

  def deleted?
    deleted_at.present?
  end

  def pinned?
    pinned_at.present?
  end

  def forwarded?
    forwarded_from_name.present?
  end

  # Одноразовое сообщение, содержимое которого этому человеку показывать нельзя. Автор
  # исключён: он и так знает, что отправил, а без этого не видел бы собственную переписку.
  def sealed_for?(viewer)
    view_once? && !deleted? && viewer.present? && viewer.id != user_id
  end

  # any? по загруженной связи, а не exists?: просмотры предзагружены в with_chat_payload,
  # и запрос на каждое сообщение страницы здесь был бы лишним.
  def viewed_by?(viewer)
    viewer.present? && message_views.any? { |view| view.user_id == viewer.id }
  end

  def starred_by?(viewer)
    viewer.present? && starred_messages.any? { |starred| starred.user_id == viewer.id }
  end

  # Отмечает сообщение открытым. Повторный вызов ничего не меняет: содержимое отдаётся
  # один раз, и «пересмотреть» его нельзя даже перезагрузкой страницы.
  def mark_viewed!(viewer)
    MessageView.create!(message: self, user: viewer)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  # Мягкое удаление: тело стираем сразу, запись оставляем ради ссылок из ответов.
  # Открепляем заодно — закреплённой пустой строки в панели быть не должно.
  # Файлы удаляем физически: держать блобы у стёртого сообщения незачем.
  # Опрос уносим с ними: голосовать в удалённом сообщении не в чем, а его результаты —
  # такое же содержимое, как текст, и после удаления их держать не за чем.
  def soft_delete!
    update!(deleted_at: Time.current, body: DELETED_BODY, pinned_at: nil, quote_text: nil)
    message_reactions.destroy_all
    message_attachments.destroy_all
    poll&.destroy
    starred_messages.destroy_all
  end

  # Единая форма сообщения для REST-истории и для WS-broadcast,
  # чтобы realtime и история гарантированно совпадали по структуре.
  def as_chat_json(viewer: nil)
    return blocked_chat_json if hidden_from?(viewer)
    return sealed_view_once_json(viewer) if sealed_for?(viewer)

    revealed_chat_json(viewer)
  end

  # Полная форма одноразового сообщения. Отдельным методом, потому что отдаётся ровно однажды —
  # по явному запросу получателя, а не на каждой загрузке истории, как обычное сообщение.
  def revealed_chat_json(viewer = nil)
    {
      id: id,
      room_id: room_id,
      body: body,
      author: {id: user_id, name: user.name, external_id: user.external_id, avatar_url: user.avatar_url},
      created_at: created_at.iso8601,
      edited_at: edited_at&.iso8601,
      pinned_at: pinned_at&.iso8601,
      deleted: deleted?,
      reply_to: reply_to_json(viewer),
      reactions: reactions_json,
      attachments: message_attachments.map(&:as_chat_json),
      forwarded_from: forwarded_from_json,
      link_preview: parsed_link_preview,
      # У ответа счётчик относится к его корню: realtime-кадр сразу обновляет кнопку
      # «Обсудить» в основной ленте, не дожидаясь следующего REST-запроса.
      thread_root_id: thread_root_id,
      thread_reply_count: discussion_reply_count,
      # Считается под получателя: подсветка пузыря «вас упомянули» — его личная метка,
      # а broadcast и так строится каждому участнику отдельно.
      mentions_me: mentions?(viewer),
      # Тихое сообщение доставляется как обычное — молчат только звук и системное окно.
      silent: silent,
      # Момент самоуничтожения: пузырь показывает по нему обратный отсчёт.
      expires_at: expires_at&.iso8601,
      view_once: view_once,
      # Автору важно знать, открыли его одноразовое или нет; получателю — что он уже смотрел.
      view_once_opened: viewed_by?(viewer),
      view_once_viewers_count: message_views.size,
      # Цитата фрагмента: в ответе показывается только выделенный кусок исходного сообщения.
      quote_text: quote_text,
      starred: starred_by?(viewer),
      poll: poll&.as_chat_json(viewer: viewer)
    }
  end

  # Кого упомянули: id участников комнаты, которых разобрали из тела. Автора среди них нет —
  # упоминать самого себя смысла не имеет, а бейдж «вас упомянули» он бы получал на каждое своё сообщение.
  def mentioned_user_ids
    message_mentions.pluck(:user_id)
  end

  # any? по загруженной связи, а не exists?: строки упоминаний предзагружены в with_chat_payload,
  # и запрос на каждое сообщение страницы здесь был бы лишним.
  def mentions?(user)
    user.present? && message_mentions.any? { |mention| mention.user_id == user.id }
  end

  def discussion_root?
    thread_root_id.nil?
  end

  def discussion_reply_count
    return thread_replies.visible.count if discussion_root?

    thread_root&.thread_replies&.visible&.count || 0
  end

  # Ссылки сообщения: и вставленные инструментом композера (<a href>), и просто набранные текстом —
  # руками URL пишут чаще, чем оформляют ссылкой.
  def links
    (body.to_s.scan(/href="(#{LINK_PATTERN.source})"/i).flatten + plain_body.to_s.scan(LINK_PATTERN)).uniq
  end

  # Разворачиваем только первую: карточка на каждую ссылку превратила бы пузырь в простыню.
  def first_link
    links.first
  end

  # Ставит в очередь разворачивание ссылки. Правка тела сбрасывает старую карточку:
  # ссылка могла смениться, и показывать превью от прошлой нельзя.
  def enqueue_link_preview
    update_column(:link_preview, nil) if link_preview.present?
    LinkPreviewJob.perform_later(id) if first_link.present?
  end

  # Карточка ссылки лежит текстом (SQLite без json-типа) — наружу отдаём объектом.
  def parsed_link_preview
    return if link_preview.blank?

    JSON.parse(link_preview)
  rescue JSON::ParserError
    nil
  end

  # Короткая подпись для превью в списке чатов и в результатах поиска:
  # у сообщения с вложением текста может не быть вовсе.
  def preview_text
    # Одноразовое не раскрываем даже строкой в списке чатов: там его прочитал бы кто угодно,
    # заглянувший в чужой экран, и «посмотреть один раз» перестало бы что-либо значить.
    return "Одноразовое сообщение" if view_once?
    return "Опрос: #{poll.question}" if poll

    return plain_body if plain_body.present?

    attachment = message_attachments.first
    return "" if attachment.nil?

    case attachment.kind
    when "image" then "Фото"
    when "video" then "Видео"
    when "voice" then "Голосовое сообщение"
    when "audio" then "Аудио"
    else attachment.filename
    end
  end

  def hidden_from?(viewer)
    viewer.present? && room.group? && UserBlock.exists?(blocker_id: viewer.id, blocked_id: user_id)
  end

  private

  # Клиент тоже санитизирует разметку перед dangerouslySetInnerHTML, но очищаем её ещё и
  # на записи: история не должна хранить активный HTML, который может отдать другой клиент.
  def sanitize_body
    self.body = self.class.sanitized_body(body)
  end

  def apply_room_expiry
    self.expires_at ||= room&.message_expiry_at
  end

  # Джоба удаляет сообщение ровно в срок, чтобы оно исчезало и из открытого чата. Очередь демо
  # живёт в памяти процесса, поэтому она не единственная защита: просроченное подметается ещё
  # и при открытии комнаты.
  def schedule_expiry
    return if expires_at.blank?

    ExpireMessageJob.set(wait_until: expires_at).perform_later(id)
  end

  # Текстовая копия тела — для поиска и превью. HTML собирает композер, теги известны.
  def sync_plain_body
    self.plain_body = body_to_plain_text if body_changed?
  end

  # Упоминания пересобираются на каждое изменение тела: правка может и добавить упоминание,
  # и убрать его, а мягкое удаление стирает тело целиком.
  def sync_mentions
    user_ids = resolved_mention_user_ids
    existing_ids = message_mentions.pluck(:user_id)

    message_mentions.where(user_id: existing_ids - user_ids).destroy_all
    (user_ids - existing_ids).each { |mentioned_id| message_mentions.create!(user_id: mentioned_id) }
  end

  # external_id из разметки — данные от клиента, поэтому упоминанием считается только участник
  # этой же комнаты. Иначе любой мог бы «упомянуть» постороннего и прислать ему уведомление.
  def resolved_mention_user_ids
    external_ids = mentioned_external_ids
    return [] if external_ids.empty?

    room.users.where(external_id: external_ids).where.not(id: user_id).pluck(:id)
  end

  def mentioned_external_ids
    return [] if body.blank?

    Nokogiri::HTML5.fragment(body)
      .css("[data-mention]")
      .filter_map { |node| node["data-mention"].to_s.strip.presence }
      .uniq
      .first(MAX_MENTIONS)
  end

  def body_to_plain_text
    return "" if body.blank?

    self.class.plain_text_from_html(body)
  end

  # Цитата — только то, что рисуется в пузыре: без вложенных ответов и реакций.
  # Одноразовое в цитате не раскрываем: иначе его содержимое утекало бы ответом на него.
  def reply_to_json(viewer)
    return if reply_to.nil? || reply_to.deleted? || reply_to.hidden_from?(viewer) || reply_to.sealed_for?(viewer)

    {
      id: reply_to.id,
      body: reply_to.body,
      # Готовое превью: у цитируемого вложения текста может не быть вовсе.
      preview: reply_to.preview_text,
      author_name: reply_to.user.name
    }
  end

  # Одноразовое сообщение до открытия (и после него) едет без содержимого: сохранить его
  # клиент не должен даже в кэше, иначе «посмотреть один раз» превращается в оформление.
  # Форма кадра та же, что у обычного сообщения, — клиент апсертит его по id, не разбирая типов.
  def sealed_view_once_json(viewer)
    revealed_chat_json(viewer).merge(
      body: "",
      attachments: [],
      link_preview: nil,
      poll: nil,
      reactions: [],
      # Чем было сообщение — чтобы пузырь подписал заглушку «Фото» или «Сообщение».
      view_once_kind: message_attachments.first&.kind || "text",
    )
  end

  # Содержимое скрытого сообщения не выдаём клиенту вовсе: это важнее, чем замаскировать его CSS-ом.
  def blocked_chat_json
    {
      id: id,
      room_id: room_id,
      body: "",
      author: {id: user_id, name: user.name, external_id: user.external_id, avatar_url: user.avatar_url},
      created_at: created_at.iso8601,
      edited_at: nil,
      pinned_at: nil,
      deleted: false,
      blocked: true,
      reply_to: nil,
      reactions: [],
      attachments: [],
      forwarded_from: nil,
      link_preview: nil,
      thread_root_id: thread_root_id,
      thread_reply_count: discussion_reply_count,
      # Упоминание от заблокированного не подсвечиваем: его содержимое мы и не показали.
      mentions_me: false,
      silent: silent,
      expires_at: nil,
      view_once: false,
      view_once_opened: false,
      view_once_viewers_count: 0,
      quote_text: nil,
      starred: false,
      poll: nil
    }
  end

  # У пересланного автор копии — тот, кто переслал; оригинального автора несём отдельно,
  # потому что исходное сообщение лежит в чужой комнате и читателю недоступно.
  def forwarded_from_json
    return unless forwarded?

    {name: forwarded_from_name, external_id: forwarded_from_external_id}
  end

  # Реакции группируются по эмодзи. Кто из них «я» — считает фронт,
  # потому что broadcast один на всех подписчиков комнаты.
  #
  # Имена едут вместе с идентификаторами: подсказка «кто отреагировал» иначе собиралась бы
  # по составу комнаты, и вышедший из группы участник оставался бы в ней безымянным.
  def reactions_json
    message_reactions.group_by(&:emoji).map do |emoji, reactions|
      {
        emoji: emoji,
        external_ids: reactions.map { |reaction| reaction.user.external_id },
        users: reactions.map { |reaction| {external_id: reaction.user.external_id, name: reaction.user.name} }
      }
    end
  end
end
