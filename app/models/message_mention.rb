# frozen_string_literal: true

# Кого упомянули в сообщении. Разбирается из тела при сохранении: разметку пишет композер,
# но прийти она может от любого клиента, поэтому в строки попадают только участники комнаты.
class MessageMention < ApplicationRecord
  belongs_to :message
  belongs_to :user

  validates :user_id, uniqueness: {scope: :message_id}
end
