# frozen_string_literal: true

class CreateStarredMessages < ActiveRecord::Migration[8.1]
  def change
    # Отметка «важное» — личная: одно и то же сообщение группы один участник отметил, другой нет.
    # Это не «Избранное»: там лежит копия сообщения, а здесь только ссылка на оригинал.
    create_table :starred_messages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true

      t.timestamps
    end

    add_index :starred_messages, %i[user_id message_id], unique: true
    # Список отмеченных открывается свежими сверху — по этому индексу и сортируется.
    add_index :starred_messages, %i[user_id created_at]
  end
end
