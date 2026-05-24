# Be sure to restart your server when you modify this file.

# Разрешаем фронту (dev и деплой) ходить в REST API с другого origin.
# Список origin'ов задаётся через ENV CORS_ORIGINS (через запятую),
# по умолчанию — локальный dev-фронт на :3000.
cors_origins = ENV.fetch("CORS_ORIGINS", "http://localhost:3000").split(",").map(&:strip).reject(&:blank?)
if Rails.env.production? && (cors_origins.empty? || cors_origins.include?("*"))
  raise "CORS_ORIGINS must list explicit production frontend origins"
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*cors_origins)

    resource "*",
      headers: :any,
      methods: %i[get post put patch delete options head]
  end
end
