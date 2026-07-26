# frozen_string_literal: true

class CreateScheduledMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_messages do |t|
      t.references :room, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :deliver_at, null: false
      t.datetime :cancelled_at
      t.datetime :delivered_at

      t.timestamps
    end

    add_index :scheduled_messages, %i[user_id deliver_at]
    add_index :scheduled_messages, :deliver_at
  end
end
