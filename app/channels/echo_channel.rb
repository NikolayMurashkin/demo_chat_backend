# frozen_string_literal: true

class EchoChannel < ApplicationCable::Channel
  # Вызывается, когда клиент подписался на канал.
  def subscribed
    # Тестовый broadcast-канал нельзя оставлять доступным в production: он позволял
    # любому сокету рассылать произвольные данные всем подписчикам.
    reject
  end

  # Вызывается при отписке/отключении — здесь освобождаем ресурсы.
  def unsubscribed
    stop_all_streams
  end
end
