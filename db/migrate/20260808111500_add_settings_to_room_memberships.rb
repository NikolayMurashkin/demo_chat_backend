# frozen_string_literal: true

class AddSettingsToRoomMemberships < ActiveRecord::Migration[8.1]
  def change
    # Личные настройки чата: у каждого участника свои, поэтому живут на связи, а не на комнате.
    # Приглушённый чат остаётся в списке и продолжает считать непрочитанные — молчит только
    # звук и системное окно.
    add_column :room_memberships, :muted_at, :datetime
    # Закреплённый чат стоит выше остальных независимо от времени последнего сообщения.
    add_column :room_memberships, :pinned_at, :datetime
    # Помеченный непрочитанным вручную: точка в списке горит, пока чат не откроют.
    add_column :room_memberships, :marked_unread_at, :datetime

    # Порядок списка чатов считается на каждый GET /api/rooms — закреплённые выбираются по нему.
    add_index :room_memberships, %i[user_id pinned_at]
  end
end
