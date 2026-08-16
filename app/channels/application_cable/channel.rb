# frozen_string_literal: true

module ApplicationCable
  class Channel < ActionCable::Channel::Base
    MAX_ACTION_KEYS = 12

    # Не передаём произвольный JSON дальше в Action Cable dispatcher. Это не заменяет
    # лимит размера фрейма на ingress, но защищает channel code от невалидных команд,
    # flooding неизвестными action и чрезмерно широких объектов.
    #
    # Общий потолок кадров — по человеку, а не по паре «человек + адрес»: за одним IP сидит
    # целая команда, и общий бюджет они выедали друг у друга. Сам потолок держим заведомо
    # выше живой работы — «печатает…» и отметки о прочтении летят десятками в минуту даже
    # у одного человека, а у него ещё и пять вкладок.
    def perform_action(data)
      return unless data.is_a?(Hash) && data.size <= MAX_ACTION_KEYS
      return unless ChatRateLimiter.allow?("ws_frame:#{current_user.id}", **ChatLimits.rate(:ws_frame))

      super
    end
  end
end
