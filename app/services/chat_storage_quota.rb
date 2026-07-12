# frozen_string_literal: true

# Квоты на вложения: общая, на пользователя и на комнату.
#
# Нужны потому, что вложения лежат в самой БД (см. ActiveStorage::Service::DatabaseService):
# место кончается не «на диске», а в базе, вместе с перепиской.
#
# Проверка стоит вплотную к транзакции загрузки, а весь блок — под мьютексом: между «посчитали»
# и «записали» иначе пролезает параллельная загрузка, и лимит превышается на её размер.
# Мьютекс закрывает эту гонку только в пределах процесса; на нескольких инстансах резервирование
# придётся перенести в Redis или на advisory-локи PostgreSQL.
class ChatStorageQuota
  class Exceeded < StandardError; end

  DEFAULT_TOTAL_BYTES = 750 * 1024 * 1024
  DEFAULT_USER_BYTES = 100 * 1024 * 1024
  DEFAULT_ROOM_BYTES = 250 * 1024 * 1024

  @mutex = Mutex.new

  class << self
    def reserve_upload!(user:, room:, byte_size:)
      return yield if byte_size.zero?

      @mutex.synchronize do
        raise Exceeded, "upload_quota_exceeded" if byte_size.negative? || byte_size > total_limit
        raise Exceeded, "storage_quota_exceeded" if total_bytes + byte_size > total_limit
        raise Exceeded, "user_storage_quota_exceeded" if user_bytes(user) + byte_size > user_limit
        raise Exceeded, "room_storage_quota_exceeded" if room_bytes(room) + byte_size > room_limit

        yield
      end
    end

    private

    def total_bytes
      ActiveStorage::Blob.sum(:byte_size)
    end

    def user_bytes(user)
      MessageAttachment.joins(:message).where(messages: {user_id: user.id}).sum(:byte_size)
    end

    def room_bytes(room)
      MessageAttachment.joins(:message).where(messages: {room_id: room.id}).sum(:byte_size)
    end

    def total_limit
      env_limit("CHAT_STORAGE_TOTAL_BYTES", DEFAULT_TOTAL_BYTES)
    end

    def user_limit
      env_limit("CHAT_STORAGE_USER_BYTES", DEFAULT_USER_BYTES)
    end

    def room_limit
      env_limit("CHAT_STORAGE_ROOM_BYTES", DEFAULT_ROOM_BYTES)
    end

    def env_limit(name, default)
      configured = Integer(ENV.fetch(name, default), exception: false)
      configured&.positive? ? configured : default
    end
  end
end
