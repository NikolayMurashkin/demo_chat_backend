# frozen_string_literal: true

# Кто уже открыл одноразовое сообщение. Запись создаётся ровно один раз на человека:
# именно она, а не флаг на сообщении, закрывает содержимое обратно.
class MessageView < ApplicationRecord
  belongs_to :message
  belongs_to :user

  validates :user_id, uniqueness: {scope: :message_id}
end
