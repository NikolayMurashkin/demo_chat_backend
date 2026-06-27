# frozen_string_literal: true

class MessageAttachment < ApplicationRecord
  belongs_to :message
  has_one_attached :file

  before_destroy :remember_file_blob
  after_destroy_commit :purge_orphaned_file_blob

  KINDS = %w[image video audio voice file].freeze

  validates :kind, inclusion: {in: KINDS}
  validates :filename, presence: true, length: {maximum: UploadSafety::MAX_FILENAME_LENGTH}
  validates :content_type, inclusion: {in: UploadSafety::SAFE_CONTENT_TYPES}
  validates :byte_size, numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 25.megabytes}

  # Чем рисовать вложение, решаем по MIME: фронту не приходится разбирать content_type.
  # Голосовое отличается от обычной аудио-дорожки только тем, что его записали в чате.
  def self.kind_for(content_type, voice: false)
    return "voice" if voice

    case content_type.to_s
    when %r{\Aimage/} then "image"
    when %r{\Avideo/} then "video"
    when %r{\Aaudio/} then "audio"
    else "file"
    end
  end

  def as_chat_json
    {
      id: id,
      kind: kind,
      filename: filename,
      content_type: content_type,
      byte_size: byte_size,
      duration_ms: duration_ms,
      width: width,
      height: height,
      waveform: parsed_waveform,
      url: file_url
    }
  end

  private

  # has_one_attached удаляет связь, но сам blob намеренно не purge'ит: он может быть
  # переиспользован пересланным сообщением. После коммита пробуем убрать blob; Active Storage
  # безопасно оставит его, если у него всё ещё есть attachment.
  def remember_file_blob
    @file_blob = file.blob if file.attached?
  end

  def purge_orphaned_file_blob
    @file_blob&.purge_later
  end

  # Пики голосового лежат текстом (SQLite без json-типа) — фронту отдаём массивом.
  def parsed_waveform
    return if waveform.blank?

    JSON.parse(waveform)
  rescue JSON::ParserError
    nil
  end

  # proxy, а не redirect: аудио и видео тянутся с seek-запросами, а редирект на disk-сервис
  # сбивает кросс-доменное воспроизведение. Хост берётся из routes.default_url_options —
  # ссылка собирается и в broadcast'е, где никакого request нет.
  def file_url
    return unless file.attached?

    Rails.application.routes.url_helpers.rails_storage_proxy_url(file)
  end
end
