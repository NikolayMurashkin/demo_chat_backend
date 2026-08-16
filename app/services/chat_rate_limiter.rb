# frozen_string_literal: true

# Ограничитель частоты дорогих действий чата.
#
# Счётчики живут в памяти процесса и намеренно НЕ претендуют на распределённость: демо крутится
# одним инстансом на Render, и там этого достаточно. В продакшене класс заменяется реализацией
# поверх Redis — код каналов и контроллеров при этом не меняется, они знают только `allow?`.
#
# Окно скользящее: в корзине лежат отметки времени, а не счётчик, поэтому всплеск на границе
# периода не проходит двойной порцией, как было бы у фиксированного окна.
class ChatRateLimiter
  @mutex = Mutex.new
  @buckets = {}

  class << self
    def allow?(key, limit:, period:)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      allowed = @mutex.synchronize do
        prune!(now)
        bucket = (@buckets[key] ||= [])
        bucket.reject! { |timestamp| timestamp <= now - period }
        if bucket.size >= limit
          false
        else
          bucket << now
          true
        end
      end

      # Отсечка обязана быть видимой. Пока её не было в логах, сломанный чат выглядел как
      # «бэкенд не вывозит»: клиент про упёршийся лимит не узнаёт, кадр просто не доезжает,
      # и разбираться приходится по описанию симптомов. Пишем вне мьютекса — логгер сам
      # ходит в I/O, и держать на нём общий замок незачем.
      Rails.logger.warn("ChatRateLimiter: превышен лимит #{key} (#{limit} за #{period} с)") unless allowed

      allowed
    end

    # Счётчики живут в процессе и переживают отдельный пример теста: без сброса примеры
    # начинают влиять друг на друга, и «слишком много запросов» ловит тот, кто просто оказался
    # в наборе последним.
    def reset!
      @mutex.synchronize { @buckets = {} }
    end

    private

    # Ключ корзины содержит id и IP, то есть множество ключей задаёт клиент. Без уборки
    # перебор идентификаторов раздувал бы хеш неограниченно, поэтому пустые и протухшие корзины
    # выбрасываем, а общий размер держим под потолком.
    def prune!(now)
      @buckets.delete_if { |_key, timestamps| timestamps.empty? || timestamps.max <= now - 300 }
      @buckets.shift while @buckets.size > 10_000
    end
  end
end
