# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    MAX_CONNECTIONS_PER_USER = 5
    MAX_CONNECTIONS_PER_IP_PER_MINUTE = 30

    def connect
      reject_unauthorized_connection unless allowed_websocket_origin?
      reject_unauthorized_connection unless ChatRateLimiter.allow?(
        "ws_connect:#{request.remote_ip}", limit: MAX_CONNECTIONS_PER_IP_PER_MINUTE, period: 60,
      )

      self.current_user = find_verified_user
      presence_state = Presence.connect(current_user.id, limit: MAX_CONNECTIONS_PER_USER)
      reject_unauthorized_connection if presence_state.nil?

      @presence_registered = true
      # Первый сокет юзера — он «появился в сети»; всем, с кем есть общая комната, шлём событие.
      broadcast_presence(online: true) if presence_state == :first
    end

    def disconnect
      return if current_user.nil? || !@presence_registered
      return unless Presence.disconnect(current_user.id)

      # update_column, а не update: колонка служебная, дёргать колбэки и валидации незачем.
      current_user.update_column(:last_seen_at, Time.current)
      broadcast_presence(online: false)
    end

    # Каналы не получают request напрямую. Не раскрываем его целиком — им нужен
    # только IP для ключей rate limit.
    def remote_ip
      request.remote_ip
    end

    private

    # Демо-идентификация: личность приходит в query-параметрах cable-URL
    # (?external_id=...&name=...). В проде здесь была бы валидация токена.
    def find_verified_user
      user = User.upsert_from_external(
        external_id: request.params[:external_id],
        name: request.params[:name],
      )
      user || reject_unauthorized_connection
    end

    # Action Cable проверяет origin до вызова connect, а эта проверка дублирует правило
    # в самом connection class. Так оно не исчезнет из-за ошибочной env-конфигурации.
    def allowed_websocket_origin?
      origin = request.headers["Origin"].to_s
      allowed_origins = ENV.fetch("CORS_ORIGINS", "http://localhost:3000").split(",").map(&:strip).reject(&:blank?)

      origin.present? && allowed_origins.include?(origin)
    end

    # Статус нужен только тем, кто видит этого юзера в своих чатах — остальным он ни о чём.
    def broadcast_presence(online:)
      payload = {
        type: "presence",
        external_id: current_user.external_id,
        online: online,
        last_seen_at: current_user.last_seen_at&.iso8601
      }

      User.sharing_rooms_with(current_user).find_each { |peer| UserChannel.broadcast_to(peer, payload) }
    end
  end
end
