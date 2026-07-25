# frozen_string_literal: true

class AddSavedForToRooms < ActiveRecord::Migration[8.1]
  def change
    # Одна персональная комната «Избранное» на пользователя. Это не личка с самим собой:
    # у неё отдельная семантика и она не участвует в правилах групповых чатов.
    add_reference :rooms, :saved_for, index: {unique: true}, foreign_key: {to_table: :users}
  end
end
