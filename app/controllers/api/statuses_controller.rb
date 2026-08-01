# frozen_string_literal: true

module Api
  class StatusesController < BaseController
    # GET /api/status — текущий статус, чтобы селектор корректно переживал перезагрузку страницы.
    def show
      render json: chat_status_json(current_user)
    end

    # PATCH /api/status { status: "online" | "dnd" | "away", status_text: "..." }
    def update
      status = params[:status]
      return render json: {error: "invalid_status"}, status: :unprocessable_entity unless User::CHAT_STATUSES.include?(status)

      # Поле подписи необязательное: пустое значение означает стандартный текст выбранного статуса.
      # Непустой текст принимаем только строкой, затем нормализуем и проверяем максимум в 50 графем.
      raw_text = params[:status_text]
      return render json: {error: "invalid_status_text"}, status: :unprocessable_entity unless raw_text.nil? || raw_text.is_a?(String)

      # Только реально пустое поле означает «использовать стандартный текст».
      # Строка из пробелов — это некорректный введённый статус, а не отсутствие значения.
      text = raw_text.nil? || raw_text.empty? ? User.default_chat_status_text(status) : User.normalize_chat_status_text(raw_text)
      return render json: {error: "invalid_status_text"}, status: :unprocessable_entity unless text

      current_user.update!(chat_status: status, chat_status_text: text)
      broadcast_status

      render json: chat_status_json(current_user)
    end

    private

    def chat_status_json(user)
      {status: user.chat_status, status_text: user.chat_status_text}
    end

    # Статус получают только сам пользователь (для других его вкладок) и собеседники с общей комнатой.
    def broadcast_status
      payload = chat_status_json(current_user).merge(type: "status", external_id: current_user.external_id)
      # Так открытые вкладки того же пользователя тоже сразу увидят новую подпись.
      UserChannel.broadcast_to(current_user, payload)
      User.sharing_rooms_with(current_user).find_each { |peer| UserChannel.broadcast_to(peer, payload) }
    end
  end
end
