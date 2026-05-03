# frozen_string_literal: true

class User < ApplicationRecord
  MAX_EXTERNAL_ID_LENGTH = 128
  MAX_NAME_LENGTH = 120
  MAX_AVATAR_URL_LENGTH = 2_048
  MAX_CHAT_STATUS_TEXT_LENGTH = 50
  EXTERNAL_ID_PATTERN = /\A[a-zA-Z0-9._:-]+\z/
  CHAT_STATUSES = %w[online dnd away].freeze
  DEFAULT_CHAT_STATUS_TEXTS = {
    "online" => "В сети",
    "dnd" => "Не беспокоить",
    "away" => "Отошел"
  }.freeze
  has_many :room_memberships, dependent: :destroy
  has_many :rooms, through: :room_memberships
  has_many :visible_room_memberships, -> { where(visible: true) }, class_name: "RoomMembership"
  has_many :visible_rooms, through: :visible_room_memberships, source: :room
  has_many :messages, dependent: :destroy
  has_many :message_reactions, dependent: :destroy
  has_many :message_views, dependent: :destroy
  has_many :starred_messages, dependent: :destroy
  has_many :poll_votes, dependent: :destroy
  has_many :chat_folders, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :user
  has_many :initiated_blocks, class_name: "UserBlock", foreign_key: :blocker_id, dependent: :destroy
  has_many :received_blocks, class_name: "UserBlock", foreign_key: :blocked_id, dependent: :destroy

  validates :chat_status, inclusion: {in: CHAT_STATUSES}
  validate :chat_status_text_is_safe

  # Все, с кем есть хотя бы одна общая комната: только им адресуются presence-события.
  def self.sharing_rooms_with(user)
    where(id: RoomMembership.where(room_id: user.rooms.select(:id)).where.not(user_id: user.id).select(:user_id))
  end

  def online?
    Presence.online?(id)
  end

  # Демо-идентификация: находим/создаём юзера по внешнему id (id аккаунта фронта).
  # Имя фиксируем ТОЛЬКО при создании — чтобы переподключение существующего юзера
  # было чтением без записи (иначе конкурентные апдейты имени лочат SQLite).
  # Аватар догоняем один раз: юзер мог появиться из WS-подключения (там его нет)
  # или из чужого приглашения в группу — но переписывать уже известный не станем.
  # В проде это заменит валидация JWT — сейчас личность приходит от фронта.
  def self.upsert_from_external(external_id:, name: nil, avatar_url: nil)
    external_id = external_id.to_s.strip
    return unless external_id.length.between?(1, MAX_EXTERNAL_ID_LENGTH) && external_id.match?(EXTERNAL_ID_PATTERN)

    name = normalized_name(name, external_id)
    avatar_url = normalized_avatar_url(avatar_url)

    # HTTP-запрос и WS-подключение одного нового пользователя могут стартовать одновременно.
    # create_or_find_by! сначала выполняет обычный INSERT и ловит RecordNotUnique — PostgreSQL
    # всё равно пишет такие конфликты как ERROR. Нативный ON CONFLICT DO NOTHING не создаёт
    # ни ошибки, ни 500: после него оба запроса читают одну и ту же запись.
    now = Time.current
    insert_all(
      [{external_id: external_id, name: name, avatar_url: avatar_url, created_at: now, updated_at: now}],
      unique_by: :index_users_on_external_id,
    )
    user = find_by!(external_id: external_id)

    user.update(avatar_url: avatar_url) if user.avatar_url.blank? && avatar_url.present?
    user
  end

  def self.normalized_name(name, external_id)
    name.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").squish.truncate(MAX_NAME_LENGTH).presence || "User #{external_id.truncate(MAX_NAME_LENGTH - 5)}"
  end
  private_class_method :normalized_name

  # Статус — plain text, не разметка. Убираем управляющие/format-символы (включая bidi) и
  # HTML-скобки, нормализуем Unicode и пробелы. Лимит задан в видимых графемах, а не UTF-16-единицах.
  def self.normalize_chat_status_text(value)
    return unless value.is_a?(String)

    text = value
      .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      .unicode_normalize(:nfc)
      .gsub(/[\p{Cc}\p{Cf}]/, "")
      .delete("<>")
      .gsub(/\p{Space}+/, " ")
      .strip

    return if text.blank? || text.scan(/\X/).length > MAX_CHAT_STATUS_TEXT_LENGTH

    text
  end

  def self.default_chat_status_text(status)
    DEFAULT_CHAT_STATUS_TEXTS.fetch(status)
  end

  def chat_status_text_is_safe
    normalized = self.class.normalize_chat_status_text(chat_status_text)
    return if normalized == chat_status_text

    errors.add(:chat_status_text, "must be plain text no longer than #{MAX_CHAT_STATUS_TEXT_LENGTH} characters")
  end

  # Ссылка на картинку из внешнего профиля. Публичный метод: тем же правилом проверяется
  # и аватар группы, который задаёт её создатель.
  def self.normalized_avatar_url(value)
    url = value.to_s.strip
    return if url.blank? || url.length > MAX_AVATAR_URL_LENGTH

    uri = URI.parse(url)
    uri.to_s if uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end
end
