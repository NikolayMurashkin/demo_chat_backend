class CreateActiveStorageDbFiles < ActiveRecord::Migration[7.2]
  def change
    create_table :active_storage_db_files do |t|
      t.string :key, null: false
      t.binary :data, null: false
      t.bigint :byte_size, null: false

      t.timestamps
    end

    add_index :active_storage_db_files, :key, unique: true
  end
end
