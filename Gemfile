source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# Use sqlite3 as the database for Active Record (development/test)
gem "sqlite3", ">= 1.4"
# Postgres — durable-БД в production (Render free Postgres переживает сон/редеплой, в отличие от эфемерной ФС)
gem "pg", "~> 1.5"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"
# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Check the lockfile for published vulnerable dependencies.
  gem "bundler-audit", "~> 0.9", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-rspec", "~> 3.8", require: false
  gem "rubocop-rspec_rails", "~> 2.32", require: false

  # The same test stack used by the maintained Ruby services. WebMock keeps any future
  # integration tests for link previews from accidentally reaching the public internet.
  gem "factory_bot_rails", "~> 6.5"
  gem "faker", "~> 3.5"
  gem "rspec-rails", "~> 8.0"
  gem "simplecov", "~> 1.1", require: false
  gem "webmock", "~> 3.26"
end
