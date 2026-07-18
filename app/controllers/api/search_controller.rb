# frozen_string_literal: true

module Api
  class SearchController < BaseController
    ROOMS_LIMIT = 20
    MESSAGES_LIMIT = 30
    MAX_QUERY_LENGTH = 200

    # GET /api/search?q=<текст>
    # Глобальный поиск для панели диалогов: сначала подходящие чаты, затем сообщения
    # из всех комнат юзера — с указанием комнаты, чтобы клик открывал нужный диалог.
    def index
      raw = params[:q].to_s.strip
      return render json: {error: "query_too_long"}, status: :unprocessable_entity if raw.length > MAX_QUERY_LENGTH

      query = MessageSearchQuery.new(raw)
      return render json: {rooms: [], messages: []} if query.blank?

      # Чаты ищутся только по названию: фильтры сообщений (from:, has:) к ним неприменимы,
      # а с ними в выдачу попадали бы все чаты подряд.
      rooms = query.text.present? ? matching_rooms(query.text) : []
      render json: {rooms: rooms, messages: matching_messages(query)}
    end

    private

    def rooms_scope
      current_user.visible_rooms.includes(:users)
    end

    # Личка названия не хранит — её имя это имя собеседника, поэтому фильтруем в руби
    # по тому же display_name_for, что видит юзер в списке.
    def matching_rooms(query)
      downcased = query.downcase

      rooms_scope
        .select { |room| room.display_name_for(current_user).downcase.include?(downcased) }
        .first(ROOMS_LIMIT)
        .map { |room| {id: room.id, name: room.display_name_for(current_user), is_group: room.group?} }
    end

    def matching_messages(query)
      rooms_by_id = rooms_scope.index_by(&:id)

      query
        .apply(Message.visible, viewer: current_user)
        .where(room_id: rooms_by_id.keys)
        .with_chat_payload
        .order(id: :desc)
        .limit(MESSAGES_LIMIT)
        .reject { |message| message.hidden_from?(current_user) }
        .map do |message|
          room = rooms_by_id[message.room_id]
          message.as_chat_json(viewer: current_user).merge(room: {id: room.id, name: room.display_name_for(current_user)})
        end
    end
  end
end
