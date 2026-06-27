# Ссылки на вложения собираются в том числе в WS-broadcast'е, где request недоступен,
# поэтому хост задаётся глобально. RENDER_EXTERNAL_URL Render подставляет сам — без него
# задеплоенный сервис раздавал бы ссылки на localhost, и ни одно вложение не открылось бы.
public_url = URI.parse(
  ENV["CHAT_PUBLIC_URL"].presence || ENV["RENDER_EXTERNAL_URL"].presence || "http://localhost:3100"
)

Rails.application.routes.default_url_options = {
  protocol: public_url.scheme,
  host: public_url.host,
  port: public_url.port
}
