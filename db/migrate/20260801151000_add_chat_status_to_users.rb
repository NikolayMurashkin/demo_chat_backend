# frozen_string_literal: true

class AddChatStatusToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :chat_status, :string, null: false, default: "online"
    # text, а не varchar(255): 50 видимых emoji-графем могут занимать больше 255 codepoints.
    add_column :users, :chat_status_text, :text, null: false, default: "В сети"
  end
end
