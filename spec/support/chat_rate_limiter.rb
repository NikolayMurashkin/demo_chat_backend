# frozen_string_literal: true

# Лимиты частоты считаются по адресу, а он у всех примеров один — 127.0.0.1. Без сброса
# бюджет отправок съедают предыдущие примеры, и падает тот, кто оказался в наборе последним.
RSpec.configure do |config|
  config.before { ChatRateLimiter.reset! }
end
