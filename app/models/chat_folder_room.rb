# frozen_string_literal: true

class ChatFolderRoom < ApplicationRecord
  belongs_to :chat_folder
  belongs_to :room

  validates :room_id, uniqueness: {scope: :chat_folder_id}
end
