class AddModerationFieldsToMessages < ActiveRecord::Migration[7.2]
  def change
    # Мягкое удаление: сообщение остаётся, чтобы ответы на него не осиротели,
    # но тело не отдаётся и клиент убирает его из ленты.
    add_column :messages, :deleted_at, :datetime
    add_column :messages, :edited_at, :datetime
  end
end
