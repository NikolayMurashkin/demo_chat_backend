# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    before_action :require_user
    before_action :throttle_request

    # Не отдаём 500, если фронт спросил несуществующую комнату/ресурс.
    rescue_from ActiveRecord::RecordNotFound do
      render json: {error: "not_found"}, status: :not_found
    end

    private

    # Демо-идентификация из query-параметров (external_id / name) — так же,
    # как в cable-URL, и с корректной UTF-8 (кириллица в заголовках ломается).
    # В проде — валидация токена.
    def current_user
      @current_user ||= User.upsert_from_external(
        external_id: params[:external_id],
        name: params[:name],
        avatar_url: params[:avatar_url],
      )
    end

    def require_user
      render json: {error: "unauthorized"}, status: :unauthorized unless current_user
    end

    def throttle_request
      return if within_rate_limits?

      render json: {error: "rate_limited"}, status: :too_many_requests
    end

    # Лимит по адресу остаётся грубым потолком: external_id приходит от клиента, и без него
    # бюджет обнулялся бы сменой личности. Но основной счёт ведём по пользователю — иначе два
    # клиента за одним адресом (демо на одной машине, офисный NAT) делят лимит и глушат друг
    # другу загрузку истории, а чат молча остаётся без обновлений.
    def within_rate_limits?
      ChatRateLimiter.allow?("http_ip:#{request.remote_ip}", limit: 600, period: 60) &&
        ChatRateLimiter.allow?("http:#{current_user.id}:#{request.remote_ip}", limit: 120, period: 60)
    end

    # online/last_seen_at едут прямо в составе участников: отдельная ручка presence не нужна,
    # а дальше статус двигают события из UserChannel.
    def member_json(user)
      {
        id: user.id,
        name: user.name,
        external_id: user.external_id,
        avatar_url: user.avatar_url,
        online: user.online?,
        last_seen_at: user.last_seen_at&.iso8601,
        status: user.chat_status,
        status_text: user.chat_status_text
      }
    end

    # Участники приходят с фронта как [{ external_id:, name:, avatar_url: }] —
    # заводим тех, кого ещё не видели (аватар берём из профиля на фронте).
    def upsert_members(members)
      Array(members).filter_map do |member|
        User.upsert_from_external(
          external_id: member[:external_id],
          name: member[:name],
          avatar_url: member[:avatar_url],
        )
      end
    end
  end
end
