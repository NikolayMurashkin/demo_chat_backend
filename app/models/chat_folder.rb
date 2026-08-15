# frozen_string_literal: true

# Папка чатов — личная вкладка над списком диалогов. Состав хранится ссылками на комнаты:
# выход из чата убирает его из папок сам, без отдельной уборки.
class ChatFolder < ApplicationRecord
  MAX_NAME_LENGTH = 40
  MAX_FOLDERS_PER_USER = 10
  MAX_ROOMS_PER_FOLDER = 100

  belongs_to :user
  has_many :chat_folder_rooms, dependent: :destroy
  has_many :rooms, through: :chat_folder_rooms

  validates :name, presence: true, length: {maximum: MAX_NAME_LENGTH}

  # Комнаты папки, отфильтрованные по текущему составу владельца: чат, из которого он вышел,
  # в папке остаётся строкой связи, но вкладка не должна о нём знать.
  def room_ids_for_owner
    rooms.where(id: user.rooms.select(:id)).pluck(:id)
  end

  def as_chat_json
    {id: id, name: name, position: position, room_ids: room_ids_for_owner}
  end
end
