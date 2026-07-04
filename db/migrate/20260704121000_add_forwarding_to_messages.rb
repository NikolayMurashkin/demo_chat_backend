class AddForwardingToMessages < ActiveRecord::Migration[7.2]
  def change
    # Автор оригинала копируется в само сообщение: оригинал живёт в чужой комнате,
    # и читатель пересланного не имеет к ней доступа — по ссылке подпись не собрать.
    add_column :messages, :forwarded_from_name, :string
    add_column :messages, :forwarded_from_external_id, :string
  end
end
