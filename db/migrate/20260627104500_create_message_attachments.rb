class CreateMessageAttachments < ActiveRecord::Migration[7.2]
  def change
    create_table :message_attachments do |t|
      t.references :message, null: false, foreign_key: true
      # image / video / audio / voice / file — определяет, чем рисовать вложение в пузыре.
      t.string :kind, null: false
      t.string :filename, null: false
      t.string :content_type
      t.integer :byte_size, null: false, default: 0
      # Только у голосовых и медиа со звуком: длительность для плеера.
      t.integer :duration_ms
      t.integer :width
      t.integer :height
      # Пики голосового сообщения (JSON-массив 0..100), посчитанные при записи на фронте.
      t.text :waveform

      t.timestamps
    end
  end
end
