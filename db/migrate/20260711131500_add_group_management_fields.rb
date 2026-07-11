class AddGroupManagementFields < ActiveRecord::Migration[7.2]
  def change
    # Создатель группы: только он переименовывает её, меняет аватар, исключает участников
    # и удаляет группу у всех. У лички владельца нет.
    add_column :rooms, :owner_id, :integer
    add_column :rooms, :avatar_url, :string
    add_index :rooms, :owner_id

    # Когда юзер последний раз был онлайн: пишется при отключении последнего сокета.
    add_column :users, :last_seen_at, :datetime

    # Развёрнутая карточка первой ссылки сообщения (JSON-строкой: SQLite без json-типа).
    add_column :messages, :link_preview, :text
  end
end
