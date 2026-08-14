# frozen_string_literal: true

module Api
  # Список личных отметок «важное». Отдельный экран: отмеченное лежит в разных чатах,
  # и собрать его в одном месте — весь смысл отметки.
  class StarredMessagesController < BaseController
    LIMIT = 100

    # GET /api/starred_messages
    def index
      starred = StarredMessage
        .where(user: current_user)
        .joins(:message)
        .where(messages: {deleted_at: nil, room_id: current_user.rooms.select(:id)})
        .includes(message: [:room, {user: []}])
        .order(created_at: :desc)
        .limit(LIMIT)

      render json: {messages: starred.filter_map { |record| starred_json(record.message) }}
    end

    private

    def starred_json(message)
      return if message.hidden_from?(current_user)

      message.as_chat_json(viewer: current_user).merge(
        room: {id: message.room_id, name: message.room.display_name_for(current_user)},
      )
    end
  end
end
