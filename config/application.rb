require_relative "boot"

require "rails"
require File.expand_path("../lib/request_body_limit", __dir__)
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # active_storage исключён: Active Storage подгружает сервис хранилища обычным require,
    # и Zeitwerk не должен управлять тем же файлом параллельно.
    config.autoload_lib(ignore: %w[assets tasks active_storage])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    config.middleware.insert_before 0, RequestBodyLimit

    # Even if a storage service ever changes its default, never render active content inline
    # from a chat attachment URL.
    config.active_storage.content_types_to_serve_as_binary += %w[
      text/html application/xhtml+xml image/svg+xml application/xml text/xml
      application/javascript text/javascript application/json application/pdf
    ]
  end
end
