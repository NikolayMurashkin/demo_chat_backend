class AddDmKeyToRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :rooms, :dm_key, :string
    add_index :rooms, :dm_key, unique: true
  end
end
