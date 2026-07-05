class AddPlainBodyToMessages < ActiveRecord::Migration[7.2]
  def up
    # Тело хранится HTML — искать по нему LIKE'ом нельзя: запрос ловил бы имена тегов
    # и не находил текст, разорванный разметкой. Держим рядом текстовую копию.
    add_column :messages, :plain_body, :text

    Message.reset_column_information
    Message.find_each { |message| message.update_column(:plain_body, message.send(:body_to_plain_text)) }
  end

  def down
    remove_column :messages, :plain_body
  end
end
