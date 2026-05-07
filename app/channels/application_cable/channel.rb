# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    MAX_ACTION_KEYS = 12
    MAX_ACTIONS_PER_MINUTE = 180

    # Не передаём произвольный JSON дальше в Action Cable dispatcher. Это не заменяет
    # лимит размера фрейма на ingress, но защищает channel code от невалидных команд,
    # flooding неизвестными action и чрезмерно широких объектов.
    def perform_action(data)
      return unless data.is_a?(Hash) && data.size <= MAX_ACTION_KEYS
      return unless ChatRateLimiter.allow?("ws_frame:#{current_user.id}:#{connection.remote_ip}", limit: MAX_ACTIONS_PER_MINUTE, period: 60)

      super
    end
  end
end
