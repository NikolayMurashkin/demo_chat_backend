# frozen_string_literal: true

class CreateMessageMentions < ActiveRecord::Migration[8.1]
  def change
    # Упоминание разбирается из тела при сохранении и хранится строками: считать «сколько
    # непрочитанных упоминаний в комнате» разбором HTML на каждый список чатов нельзя.
    create_table :message_mentions do |t|
      t.references :message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :message_mentions, %i[message_id user_id], unique: true
    # Счётчик «вас упомянули» идёт от пользователя к его сообщениям, а не наоборот.
    add_index :message_mentions, %i[user_id message_id]
  end
end
