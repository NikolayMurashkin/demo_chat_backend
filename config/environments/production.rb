require "active_support/core_ext/integer/time"
require "uri"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :database
  # URL вложения — bearer credential, поэтому он подписан и ограничен по времени. Но срок
  # должен переживать открытую вкладку: видео и голосовые дотягиваются range-запросами уже
  # после отрисовки, и на 15 минутах воспроизведение старого сообщения падало с ошибкой
  # в чате, открытом полчаса назад. Ссылка пересобирается на каждой загрузке истории,
  # так что более длинный срок не отменяет ротацию.
  config.active_storage.urls_expire_in = 12.hours

  config.action_dispatch.default_headers.merge!(
    "Content-Security-Policy" => "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=()",
    "Referrer-Policy" => "no-referrer",
    "X-Content-Type-Options" => "nosniff",
    "X-Frame-Options" => "DENY",
  )

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # WebSocket принимает только те же origin'ы, что и REST. Это не заменяет проверку
  # токена, но не даёт произвольному сайту открыть сокет к аккаунту в браузере пользователя.
  cable_origins = ENV.fetch("CORS_ORIGINS", "").split(",").map(&:strip).reject(&:blank?)
  raise "CORS_ORIGINS must list explicit production frontend origins" if cable_origins.empty? || cable_origins.include?("*")

  config.action_cable.allowed_request_origins = cable_origins
  config.action_cable.allow_same_origin_as_host = false
  config.action_cable.filter_parameters = %w[body payload sdp candidate]

  public_url = ENV["CHAT_PUBLIC_URL"].presence || ENV["RENDER_EXTERNAL_URL"].presence
  public_uri = URI.parse(public_url.to_s)
  raise "CHAT_PUBLIC_URL or RENDER_EXTERNAL_URL must contain the public HTTPS backend URL" unless public_uri.is_a?(URI::HTTPS) && public_uri.host.present?

  # Не позволяем подменённому Host влиять на маршрутизацию/редиректы.
  config.hosts = [ public_uri.host ]

  # Проба живости приходит не с публичного адреса: в Kubernetes kubelet стучится прямо на IP
  # пода, и такой запрос отвергается проверкой Host — под не проходит readiness и уходит в
  # бесконечный перезапуск, хотя приложение исправно. Health check — единственная ручка, где
  # Host не важен: она ничего не отдаёт и никуда не редиректит.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Через этот пул проходят ВСЕ операции канала — connect, subscribe, receive и рассылка
  # broadcast'ов подписчикам. Дефолтных 4 потоков хватает на пару человек: на группе
  # одновременные подключения встают в очередь и клиент ждёт confirm_subscription.
  config.action_cable.worker_pool_size = Integer(ENV.fetch("CABLE_WORKER_POOL_SIZE", 8))

  # Джобы (превью ссылок) ходят в чужую сеть с таймаутами до 5 с. Без своего ограничения
  # async-адаптер поднимает пул по числу ядер хоста и выгребает коннекты к БД у веба.
  config.active_job.queue_adapter = ActiveJob::QueueAdapters::AsyncAdapter.new(min_threads: 0, max_threads: 3)

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "backend_production"

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
