# frozen_string_literal: true

# Личная отметка «важное». В отличие от «Избранного», копии сообщения не делается: отметка
# исчезает вместе с оригиналом, зато отмеченное всегда открывается в своём чате и в контексте.
class StarredMessage < ApplicationRecord
  belongs_to :user
  belongs_to :message

  validates :message_id, uniqueness: {scope: :user_id}
end
