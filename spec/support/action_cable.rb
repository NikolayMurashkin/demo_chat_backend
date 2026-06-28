# frozen_string_literal: true

# Каналы берут из соединения только IP — он входит в ключи rate limit. ConnectionStub из
# rspec-rails повторяет лишь ActionCable::Connection::Base, поэтому нашего метода не знает,
# и verify_partial_doubles не даёт его застабить. Даём стабу такой же метод.
ActionCable::Channel::ConnectionStub.class_eval do
  def remote_ip
    "127.0.0.1"
  end
end
