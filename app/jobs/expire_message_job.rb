# frozen_string_literal: true

# Удаляет исчезающее сообщение в назначенный срок и сразу рассылает это участникам:
# открытый чат должен терять сообщение сам, без перезагрузки.
class ExpireMessageJob < ApplicationJob
  def perform(message_id)
    message = Message.visible.with_chat_payload.find_by(id: message_id)
    # Срок могли отменить (сообщение удалили руками) или сдвинуть — доверяем записи, а не джобе.
    return if message.nil? || message.expires_at.blank? || message.expires_at > Time.current

    message.soft_delete!
    message.room.broadcast_message(message)
    # Превью в списке чатов считает бэк: исчезнувшее сообщение могло быть последним.
    message.room.notify_activity
  end
end
