# frozen_string_literal: true

# Хранилище вложений в самой БД.
#
# Зачем: на free-тарифе Render нет диска, файловая система контейнера эфемерная. Стандартный
# Disk-сервис писал вложения в `storage/`, и они пропадали при каждом засыпании и редеплое,
# тогда как строки сообщений в Postgres оставались. Снаружи это выглядело как «голосовое
# не воспроизводится»: ссылка на месте, а файла за ней уже нет.
#
# Тот же Postgres, что держит переписку, переживает сон — значит и вложения переживут.
# Отдаём их только через proxy-контроллер (см. MessageAttachment#file_url), поэтому
# подписанные ссылки прямо в хранилище (private_url) не нужны.
module ActiveStorage
  class Service::DatabaseService < Service
    # Кусок, которым отдаём тело в потоковом режиме: proxy-контроллер тянет медиа
    # range-запросами, и держать всё в одной строке ответа незачем.
    CHUNK_SIZE = 5.megabytes

    class Record < ActiveRecord::Base
      self.table_name = "active_storage_db_files"
    end

    def upload(key, io, checksum: nil, **)
      instrument :upload, key: key, checksum: checksum do
        data = io.read
        ensure_integrity_of(data, checksum) if checksum

        Record.upsert(
          {key: key, data: data, byte_size: data.bytesize, created_at: Time.current, updated_at: Time.current},
          unique_by: :key,
        )
      end
    end

    def download(key, &block)
      if block_given?
        instrument :streaming_download, key: key do
          stream(key, &block)
        end
      else
        instrument :download, key: key do
          data_for(key)
        end
      end
    end

    def download_chunk(key, range)
      instrument :download_chunk, key: key, range: range do
        data_for(key).byteslice(range.begin, range.size)
      end
    end

    def delete(key)
      instrument :delete, key: key do
        Record.where(key: key).delete_all
      end
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        Record.where("key LIKE ?", "#{sanitize_like(prefix)}%").delete_all
      end
    end

    def exist?(key)
      instrument :exist, key: key do |payload|
        payload[:exist] = Record.exists?(key: key)
      end
    end

    private

    def data_for(key)
      record = Record.find_by(key: key)

      raise ActiveStorage::FileNotFoundError if record.nil?

      # В Postgres bytea приезжает строкой в бинарной кодировке — так её и отдаём.
      record.data.to_s.b
    end

    def stream(key)
      data = data_for(key)
      offset = 0

      while offset < data.bytesize
        yield data.byteslice(offset, CHUNK_SIZE)
        offset += CHUNK_SIZE
      end
    end

    # Записывать битое незачем: проверяем до вставки, а не удаляем после.
    def ensure_integrity_of(data, checksum)
      raise ActiveStorage::IntegrityError unless OpenSSL::Digest::MD5.base64digest(data) == checksum
    end

    # `_` и `%` в префиксе ключа сделали бы LIKE шире, чем задумано.
    def sanitize_like(value)
      value.gsub(/[\\%_]/) { |char| "\\#{char}" }
    end
  end
end
