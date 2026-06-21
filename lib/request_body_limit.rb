# frozen_string_literal: true

# Отсекает слишком большой запрос до того, как Rack начнёт разбирать multipart в память и на диск.
# Проверка по Content-Length стоит раньше всех остальных лимитов не ради точности (заголовок можно
# и соврать), а ради дешевизны: разбор гигабайтного тела съел бы ресурсы ещё до первой валидации.
class RequestBodyLimit
  DEFAULT_MAX_BYTES = 30 * 1024 * 1024

  def initialize(app, max_bytes: ENV.fetch("MAX_REQUEST_BODY_BYTES", DEFAULT_MAX_BYTES).to_i)
    @app = app
    @max_bytes = max_bytes
  end

  def call(env)
    content_length = env["CONTENT_LENGTH"].to_i
    return @app.call(env) if content_length <= @max_bytes

    [413, {"Content-Type" => "application/json", "Content-Length" => "29"}, ['{"error":"payload_too_large"}']]
  end
end
