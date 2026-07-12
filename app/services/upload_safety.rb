# frozen_string_literal: true

# Проверка недоверенных multipart-загрузок до того, как они дойдут до Active Storage.
#
# Заявленный браузером MIME-тип ничего не доказывает: он приходит из формы и его выбирает
# отправитель. HTML или SVG, представленный картинкой, потом отдавался бы с нашего домена —
# это готовый XSS. Поэтому тип сверяется и со списком разрешённых, и с сигнатурой самого файла.
class UploadSafety
  Result = Struct.new(:filename, :content_type, :byte_size, keyword_init: true)

  MAX_FILENAME_LENGTH = 180
  SNIFF_BYTES = 32
  SAFE_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp image/avif
    video/mp4 video/webm video/quicktime
    audio/mpeg audio/ogg audio/webm audio/mp4 audio/wav audio/x-wav
    application/pdf text/plain
  ].freeze

  class UnsafeUpload < StandardError; end

  def self.inspect!(file, max_bytes:)
    raise UnsafeUpload, "invalid_file" unless file.respond_to?(:size) && file.respond_to?(:tempfile) && file.tempfile.present?
    raise UnsafeUpload, "file_too_large" if file.size.to_i.negative? || file.size.to_i > max_bytes

    filename = safe_filename(file.original_filename)
    raise UnsafeUpload, "invalid_filename" if filename.blank?

    # MediaRecorder дописывает в заголовок части параметры — например `audio/webm;codecs=opus`.
    # Они описывают кодек, а не другой медиатип, поэтому и для списка разрешённых, и для проверки
    # сигнатуры берём только сам тип, без параметров.
    content_type = file.content_type.to_s.downcase.split(";", 2).first.to_s.strip
    raise UnsafeUpload, "unsupported_file_type" unless SAFE_CONTENT_TYPES.include?(content_type)
    raise UnsafeUpload, "invalid_file_signature" unless valid_file_signature?(file.tempfile, content_type)

    Result.new(filename: filename, content_type: content_type, byte_size: file.size.to_i)
  rescue UnsafeUpload
    raise
  rescue StandardError
    raise UnsafeUpload, "invalid_file"
  end

  def self.safe_filename(value)
    value.to_s
         .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
         .gsub(/[\\\\\/\u0000-\u001F\u007F]/, "_")
         .strip
         .truncate(MAX_FILENAME_LENGTH, omission: "")
  end
  private_class_method :safe_filename

  # Marcel, не опознав файл, намеренно откатывается к расширению имени или к заявленному браузером
  # типу. Для UX это удобно, но на границе доверия — дыра: HTML с именем `photo.png` через такой
  # фолбэк проходил. Поэтому у каждого бинарного типа требуем собственную сигнатуру в первых байтах.
  def self.valid_file_signature?(tempfile, content_type)
    tempfile.rewind
    bytes = tempfile.read(SNIFF_BYTES).to_s.b

    case content_type
    when "image/jpeg" then bytes.start_with?("\xFF\xD8\xFF".b)
    when "image/png" then bytes.start_with?("\x89PNG\r\n\x1A\n".b)
    when "image/gif" then bytes.start_with?("GIF87a", "GIF89a")
    when "image/webp" then bytes.start_with?("RIFF") && bytes[8, 4] == "WEBP"
    when "image/avif" then iso_media_file?(bytes, "avif", "avis")
    when "video/mp4", "audio/mp4" then iso_media_file?(bytes)
    when "video/quicktime" then iso_media_file?(bytes, "qt  ")
    when "video/webm", "audio/webm" then bytes.start_with?("\x1A\x45\xDF\xA3".b)
    when "audio/ogg" then bytes.start_with?("OggS")
    when "audio/wav", "audio/x-wav" then bytes.start_with?("RIFF") && bytes[8, 4] == "WAVE"
    when "audio/mpeg" then bytes.start_with?("ID3") || bytes.start_with?("\xFF\xFB".b, "\xFF\xF3".b, "\xFF\xF2".b)
    when "application/pdf" then bytes.start_with?("%PDF-")
    when "text/plain" then safe_plain_text?(tempfile)
    else false
    end
  ensure
    tempfile.rewind
  end
  private_class_method :valid_file_signature?

  def self.iso_media_file?(bytes, *brands)
    return false unless bytes[4, 4] == "ftyp"
    return true if brands.empty?

    brands.include?(bytes[8, 4])
  end
  private_class_method :iso_media_file?

  # Текстовые вложения разрешены осознанно, но активной разметке не место ни в plain text, ни на
  # пути, где браузер может заняться собственным угадыванием типа. Полноценные HTML, SVG и XML
  # остаются запрещёнными: у текста нет сигнатуры, и отличить их можно только по содержимому.
  def self.safe_plain_text?(tempfile)
    tempfile.rewind
    text = tempfile.read.to_s.force_encoding(Encoding::UTF_8)
    return false unless text.valid_encoding?

    !text.match?(/<\s*(?:!doctype|html|script|svg|\?xml)\b/i)
  ensure
    tempfile.rewind
  end
  private_class_method :safe_plain_text?
end
