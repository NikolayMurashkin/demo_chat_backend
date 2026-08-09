# frozen_string_literal: true

class AddChatFeatureColumns < ActiveRecord::Migration[8.1]
  def change
    # Канал внутри группы: та же комната, но подчинённая другой. Состав наследуется от родителя,
    # поэтому отдельной таблицы участников каналу не нужно.
    add_column :rooms, :parent_id, :integer
    add_index :rooms, :parent_id
    # Ссылка-приглашение в группу. Хранится токеном, а не id: по id ссылку можно было бы
    # подобрать перебором, а отозвать приглашение — только удалив саму группу.
    add_column :rooms, :invite_token, :string
    add_index :rooms, :invite_token, unique: true
    # Исчезающие сообщения: срок жизни задаётся на комнату, а на сообщении лежит уже готовый
    # момент удаления — смена настройки не должна задним числом двигать сроки у старых сообщений.
    add_column :rooms, :ttl_seconds, :integer

    # Архив: чат уходит из основного списка, но не удаляется и продолжает считать непрочитанные.
    add_column :room_memberships, :archived_at, :datetime
    add_index :room_memberships, %i[user_id archived_at]
    # Оформление чата — личное: один и тот же диалог у собеседников может выглядеть по-разному.
    add_column :room_memberships, :theme, :string

    # Тихая отправка: сообщение доставляется как обычно, но не даёт повода для звука и окна.
    add_column :messages, :silent, :boolean, default: false, null: false
    # Момент самоуничтожения. Индекс нужен подметанию просроченного при открытии комнаты.
    add_column :messages, :expires_at, :datetime
    add_index :messages, :expires_at
    # «Посмотреть один раз»: содержимое отдаётся получателю ровно однажды.
    add_column :messages, :view_once, :boolean, default: false, null: false
    # Цитата фрагмента: в ответе показывается только выделенный кусок исходного сообщения.
    add_column :messages, :quote_text, :text
  end
end
