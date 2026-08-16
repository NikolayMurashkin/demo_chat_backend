# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      reject_unauthorized_connection unless allowed_websocket_origin?
      reject_overloaded_connection unless within_ip_rate_limit?

      self.current_user = find_verified_user
      reject_overloaded_connection unless within_user_rate_limit?

      close_extra_connections
      presence_state = Presence.connect(current_user.id)

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

    def within_ip_rate_limit?
      ChatRateLimiter.allow?("ws_connect:#{request.remote_ip}", **ChatLimits.rate(:ws_connect_ip))
    end

    def within_user_rate_limit?
      ChatRateLimiter.allow?("ws_connect_user:#{current_user.id}", **ChatLimits.rate(:ws_connect_user))
    end

    # Перегрузка — не отказ в доступе. reject_unauthorized_connection закрывает сокет с
    # reconnect: false, и клиент больше не пытается подключиться: чат оставался мёртвым до
    # перезагрузки страницы, хотя сервер был готов принять его через минуту. Здесь закрываем
    # с reconnect: true — клиент вернётся сам, по своей выдержке.
    def reject_overloaded_connection
      close(reason: "server_busy", reconnect: true) if websocket.alive?
      # Прерываем connect. Ответный close из обработчика уже не уйдёт: сокет закрыт выше.
      raise ActionCable::Connection::Authorization::UnauthorizedError
    end

    # Место новому подключению освобождаем сами, закрывая самые старые сокеты этого же юзера.
    # Забытая вкладка не должна мешать той, в которой человек сейчас работает. Потолок при этом
    # держим заведомо выше живого сценария: пять компьютеров по три вкладки — это пятнадцать
    # сокетов, и вытеснять там нечего.
    def close_extra_connections
      # Реестр открытых сокетов есть только у настоящего сервера: под тестовым соединением
      # вытеснять нечего, а сам connect должен отработать как обычно.
      registry = server&.connections
      return if registry.nil?

      # Список меняется из других потоков — работаем по копии.
      peers = registry.dup.select { |connection| connection.current_user&.id == current_user.id }
      extra = peers.size - ChatLimits.count(:sockets_per_user) + 1
      return if extra <= 0

      peers
        .sort_by { |connection| connection.statistics[:started_at].to_i }
        .first(extra)
        .each { |connection| connection.close(reason: "replaced_by_newer_tab", reconnect: false) }
    end

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
