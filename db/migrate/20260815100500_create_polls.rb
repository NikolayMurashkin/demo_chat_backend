# frozen_string_literal: true

class CreatePolls < ActiveRecord::Migration[8.1]
  def change
    # Опрос живёт при сообщении, а не вместо него: он приходит тем же broadcast'ом,
    # попадает в историю и умеет всё, что умеет сообщение — ответ, пересылку, закрепление.
    create_table :polls do |t|
      t.references :message, null: false, foreign_key: true, index: {unique: true}
      t.string :question, null: false
      # Опрос с несколькими вариантами ответа: голос снимается повторным нажатием.
      t.boolean :multiple, default: false, null: false
      # Закрытый опрос показывает результаты, но голосовать в нём уже нельзя.
      t.datetime :closed_at

      t.timestamps
    end

    create_table :poll_options do |t|
      t.references :poll, null: false, foreign_key: true
      t.string :text, null: false
      # Порядок вариантов задал автор — сортировка по id ломалась бы при любой правке.
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :poll_options, %i[poll_id position]

    create_table :poll_votes do |t|
      t.references :poll, null: false, foreign_key: true
      t.references :poll_option, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    # Один голос за вариант. Ограничение «один вариант на опрос» для обычного опроса
    # держит код: в БД оно мешало бы опросу с несколькими ответами.
    add_index :poll_votes, %i[poll_option_id user_id], unique: true
    add_index :poll_votes, %i[poll_id user_id]
  end
end
