class AddUniqueIndexToRoomMemberships < ActiveRecord::Migration[7.2]
  def up
    # Старые дубли (если успели появиться от одновременных запросов) убираем перед индексом.
    duplicates = RoomMembership.group(:room_id, :user_id).having("COUNT(*) > 1").pluck(:room_id, :user_id)
    duplicates.each do |room_id, user_id|
      ids = RoomMembership.where(room_id: room_id, user_id: user_id).order(:id).pluck(:id)
      RoomMembership.where(id: ids.drop(1)).delete_all
    end

    add_index :room_memberships, [ :room_id, :user_id ], unique: true
  end

  def down
    remove_index :room_memberships, column: [ :room_id, :user_id ]
  end
end
