# frozen_string_literal: true

class AddVisibleToRoomMemberships < ActiveRecord::Migration[8.1]
  def change
    # Старые комнаты остаются видимыми всем участникам. Для новой пустой лички
    # получатель получает visible: false до первого отправленного сообщения.
    add_column :room_memberships, :visible, :boolean, null: false, default: true
    add_index :room_memberships, %i[user_id visible]
  end
end
