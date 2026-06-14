class AddPinnedAtToMessages < ActiveRecord::Migration[7.2]
  def change
    add_column :messages, :pinned_at, :datetime
    add_index :messages, [ :room_id, :pinned_at ]
  end
end
