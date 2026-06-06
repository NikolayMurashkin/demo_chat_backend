class AddReplyToToMessages < ActiveRecord::Migration[7.2]
  def change
    add_reference :messages, :reply_to, foreign_key: { to_table: :messages }
  end
end
