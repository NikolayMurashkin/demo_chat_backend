class CreateMessageReactions < ActiveRecord::Migration[7.2]
  def change
    create_table :message_reactions do |t|
      t.references :message, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :emoji, null: false

      t.timestamps
    end

    # Один юзер ставит конкретную эмодзи на сообщение не более одного раза.
    add_index :message_reactions, %i[message_id user_id emoji], unique: true
  end
end
