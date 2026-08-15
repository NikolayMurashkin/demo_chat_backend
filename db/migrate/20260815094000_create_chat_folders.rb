# frozen_string_literal: true

class CreateChatFolders < ActiveRecord::Migration[8.1]
  def change
    # Папки чатов — личные вкладки над списком диалогов, как в Telegram.
    create_table :chat_folders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      # Порядок вкладок задаёт владелец, поэтому он хранится, а не считается из имени.
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :chat_folders, %i[user_id position]

    # Комната лежит в папке, а не наоборот: один и тот же чат может входить сразу в несколько.
    create_table :chat_folder_rooms do |t|
      t.references :chat_folder, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true

      t.timestamps
    end

    add_index :chat_folder_rooms, %i[chat_folder_id room_id], unique: true
  end
end
