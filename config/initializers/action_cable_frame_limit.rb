# frozen_string_literal: true

# Ограничение размера входящего WS-кадра.
#
# Action Cable не выносит лимит websocket-driver в настройки Rails, а его умолчание — 64 МиБ.
# Для этого чата это избыточно на порядки: вложения ходят по HTTP, а самый большой кадр,
# который канал вообще принимает, — SDP звонка в 100 КиБ.
#
# Резать нужно ДО разбора JSON: иначе один недобросовестный клиент резервирует десятки мегабайт
# на каждое соединение, и до наших проверок дело просто не доходит. Патчим приватную переменную
# драйвера через prepend — публичной точки расширения у него нет.
module ChatActionCableFrameLimit
  MIN_FRAME_BYTES = 128 * 1024
  MAX_FRAME_BYTES = 1024 * 1024
  DEFAULT_FRAME_BYTES = 256 * 1024

  def self.bytes
    configured = Integer(ENV.fetch("ACTION_CABLE_MAX_FRAME_BYTES", DEFAULT_FRAME_BYTES), exception: false)
    configured&.clamp(MIN_FRAME_BYTES, MAX_FRAME_BYTES) || DEFAULT_FRAME_BYTES
  end

  module ClientSocketExtension
    def initialize(...)
      super
      # Драйвер создаётся внутри конструктора сокета, поэтому лимит проставляем сразу после super:
      # раньше объекта ещё нет, позже кадр уже может прийти.
      @driver.instance_variable_set(:@max_length, ChatActionCableFrameLimit.bytes)
    end
  end
end

Rails.application.config.after_initialize do
  client_socket = ActionCable::Connection::ClientSocket
  client_socket.prepend(ChatActionCableFrameLimit::ClientSocketExtension) unless client_socket < ChatActionCableFrameLimit::ClientSocketExtension
end
