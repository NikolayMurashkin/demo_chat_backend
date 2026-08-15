# frozen_string_literal: true

# Кто сейчас онлайн. Состояние держим в памяти процесса: демо крутится на одном инстансе,
# и тащить ради «зелёной точки» Redis незачем (в Фазе 2 это заменит общий стор).
#
# Считаем сокеты, а не юзеров: вкладок у человека бывает несколько, и закрытие одной
# не должно гасить статус. Наружу отдаём только моменты СМЕНЫ статуса — чтобы
# presence-события не летели на каждое переподключение.
module Presence
  MUTEX = Mutex.new
  SOCKETS = Hash.new(0)

  class << self
    # :first, если это первый сокет юзера; :connected для дополнительной вкладки.
    # Счётчик именно считает и никого не отвергает: число вкладок ограничивает Connection,
    # закрывая самые старые сокеты. Отказ здесь запирал человека до перезапуска процесса —
    # оборванные соединения (уснувший ноутбук, пропавшая сеть) сервер замечает не мгновенно,
    # и накопленные «фантомы» не давали подключиться заново.
    def connect(user_id)
      MUTEX.synchronize do
        SOCKETS[user_id] += 1
        SOCKETS[user_id] == 1 ? :first : :connected
      end
    end

    # true, если отвалился последний сокет юзера — статус сменился на «офлайн».
    def disconnect(user_id)
      MUTEX.synchronize do
        remaining = SOCKETS[user_id] - 1

        if remaining.positive?
          SOCKETS[user_id] = remaining
          false
        else
          SOCKETS.delete(user_id)
          true
        end
      end
    end

    def online?(user_id)
      MUTEX.synchronize { SOCKETS.key?(user_id) }
    end
  end
end
