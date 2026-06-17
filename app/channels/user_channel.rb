# frozen_string_literal: true

class UserChannel < ApplicationCable::Channel
  # Кадры звонка, которые канал соглашается переслать. Всё остальное молча игнорируется.
  CALL_SIGNALS = %w[call_invite call_accept call_decline call_end call_ice].freeze
  CALL_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  MAX_SDP_LENGTH = 100_000
  MAX_ICE_CANDIDATE_LENGTH = 4_096

  # Персональный канал юзера (не привязан к комнате). Клиент подписывается один раз на сессию
  # и получает лёгкие сигналы { type: "rooms_changed" } — повод перезапросить список чатов
  # и пересчитать бейдж непрочитанных, даже когда нужный чат не открыт.
  def subscribed
    return reject unless ChatRateLimiter.allow?("ws:user_subscribe:#{current_user.id}:#{connection.remote_ip}", limit: 10, period: 60)

    stream_for current_user
  end

  def unsubscribed
    stop_all_streams
  end

  # Сигналинг звонка 1:1. Канал — только реле: ничего не хранит и в медиа не участвует,
  # аудио и видео идут между браузерами напрямую (WebRTC). Сюда попадают SDP и ICE-кандидаты.
  #
  # Звонок живёт в персональном канале, а не в канале комнаты: собеседник не обязан
  # держать нужный чат открытым, а на UserChannel он подписан всю сессию.
  def call_signal(data)
    return unless CALL_SIGNALS.include?(data["type"])
    limit, period = call_rate_limit(data["type"])
    return unless ChatRateLimiter.allow?("call:#{data['type']}:#{current_user.id}:#{connection.remote_ip}", limit: limit, period: period)
    return unless valid_call_id?(data["call_id"])

    peer = callable_peer(data["to_external_id"], data["room_id"])
    return unless peer

    payload = safe_payload(data["type"], data["payload"])
    return if payload == :invalid

    UserChannel.broadcast_to(peer, {
      type: data["type"],
      call_id: data["call_id"].to_s,
      room_id: data["room_id"].to_i,
      from: {
        external_id: current_user.external_id,
        name: current_user.name,
        avatar_url: current_user.avatar_url
      },
      payload: payload
    })
  end

  private

  # Сигналинг привязан именно к личной комнате. Проверки «есть любая общая комната» недостаточно:
  # тогда участник группы мог бы передать чужой room_id и навязать вызов вне разрешённой пары.
  def callable_peer(external_id, room_id)
    return if external_id.blank? || room_id.to_i <= 0

    room = current_user.rooms.find_by(id: room_id)
    return if room.nil? || room.group?
    return if room.direct_chat_blocked_for?(current_user)

    room.users.where.not(id: current_user.id).find_by(external_id: external_id)
  end

  def valid_call_id?(value)
    value.to_s.match?(CALL_ID_PATTERN)
  end

  def call_rate_limit(type)
    case type
    when "call_ice" then [90, 60]
    when "call_invite", "call_accept" then [12, 60]
    else [20, 60]
    end
  end

  def safe_payload(type, value)
    return {} if %w[call_decline call_end].include?(type) && (value.blank? || value == {})

    payload = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    return :invalid unless payload.is_a?(Hash)

    case type
    when "call_invite", "call_accept"
      sdp = payload["sdp"]
      expected_type = type == "call_invite" ? "offer" : "answer"
      return :invalid unless sdp.is_a?(Hash) && sdp["type"] == expected_type && sdp["sdp"].is_a?(String) && sdp["sdp"].bytesize <= MAX_SDP_LENGTH

      {"sdp" => {"type" => sdp["type"], "sdp" => sdp["sdp"]}}
    when "call_ice"
      candidate = payload["candidate"]
      return :invalid unless candidate.is_a?(Hash) && candidate["candidate"].is_a?(String) && candidate["candidate"].bytesize <= MAX_ICE_CANDIDATE_LENGTH
      return :invalid unless candidate["sdpMid"].nil? || (candidate["sdpMid"].is_a?(String) && candidate["sdpMid"].bytesize <= 128)
      return :invalid unless candidate["sdpMLineIndex"].nil? || (candidate["sdpMLineIndex"].is_a?(Integer) && candidate["sdpMLineIndex"].between?(0, 99))
      return :invalid unless candidate["usernameFragment"].nil? || (candidate["usernameFragment"].is_a?(String) && candidate["usernameFragment"].bytesize <= 256)

      {"candidate" => candidate.slice("candidate", "sdpMid", "sdpMLineIndex", "usernameFragment")}
    else
      :invalid
    end
  end
end
