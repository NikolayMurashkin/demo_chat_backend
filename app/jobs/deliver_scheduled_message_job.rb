# frozen_string_literal: true

# Доставляет отложенное сообщение в назначенный срок.
#
# Джоба обязана быть идемпотентной: очередь допускает повторный запуск, а сдвиг времени
# ставит вторую джобу на ту же запись, старую при этом не отменяя. Отсюда и блокировка строки,
# и повторная проверка всех условий уже под ней.
class DeliverScheduledMessageJob < ApplicationJob
  def perform(scheduled_message_id)
    scheduled = ScheduledMessage.pending.find_by(id: scheduled_message_id)
    return if scheduled.nil? || scheduled.deliver_at > Time.current

    message = nil
    ScheduledMessage.transaction do
      # Блокируем строку и перечитываем условия: между выборкой выше и этим моментом отправку
      # могли отменить, перенести или уже доставить соседней джобой. Без lock! два параллельных
      # запуска создали бы два одинаковых сообщения.
      scheduled.lock!
      return unless scheduled.cancelled_at.nil? && scheduled.delivered_at.nil? && scheduled.deliver_at <= Time.current
      # Между планированием и доставкой автора могли исключить из группы, он мог выйти сам
      # или его успели заблокировать. Отложенное сообщение — такая же отправка, как обычная:
      # права на неё проверяем в момент доставки, а не в момент постановки.
      if !scheduled.room.room_memberships.exists?(user_id: scheduled.user_id) ||
         scheduled.room.direct_chat_blocked_for?(scheduled.user)
        scheduled.update!(cancelled_at: Time.current)
        return
      end

      message = scheduled.room.messages.create!(user: scheduled.user, body: scheduled.body)
      scheduled.update!(delivered_at: Time.current)
    end

    # Рассылка и разбор ссылки — уже вне транзакции: подписчики не должны увидеть сообщение
    # раньше, чем оно закоммичено, а превью ходит в сеть и держать на нём транзакцию нельзя.
    scheduled.room.publish_message(message)
    message.enqueue_link_preview
  end
end
