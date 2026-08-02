# frozen_string_literal: true

class CreateUserBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_blocks do |t|
      t.references :blocker, null: false, foreign_key: {to_table: :users}
      t.references :blocked, null: false, foreign_key: {to_table: :users}
      t.timestamps
    end

    add_index :user_blocks, %i[blocker_id blocked_id], unique: true
    add_check_constraint :user_blocks, "blocker_id <> blocked_id", name: "user_blocks_distinct_users"
  end
end
