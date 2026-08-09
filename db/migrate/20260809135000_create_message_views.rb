# frozen_string_literal: true

class CreateMessageViews < ActiveRecord::Migration[8.1]
  def change
    # Кто уже открыл одноразовое сообщение. Отдельная таблица, а не флаг на сообщении:
    # в группе получателей много, и каждому содержимое достаётся один раз.
    create_table :message_views do |t|
      t.references :message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :message_views, %i[message_id user_id], unique: true
  end
end
