# frozen_string_literal: true

module Api
  # Опрос приезжает в чат обычным сообщением: так он попадает в историю, поддерживает ответ,
  # пересылку и закрепление, и его не нужно доставлять отдельным каналом.
  class PollsController < BaseController
    # POST /api/rooms/:room_id/polls { question:, options: [], multiple: }
    def create
      room = current_user.rooms.find(params[:room_id])
      return render_chat_blocked if room.direct_chat_blocked_for?(current_user)
      return render json: {error: "rate_limited"}, status: :too_many_requests unless allow_create?

      question = normalized_text(params[:question], Poll::MAX_QUESTION_LENGTH)
      options = poll_options
      return render json: {error: "question_required"}, status: :unprocessable_entity if question.blank?
      return render json: {error: "options_required"}, status: :unprocessable_entity if options.size < Poll::MIN_OPTIONS
      return render json: {error: "too_many_options"}, status: :unprocessable_entity if options.size > Poll::MAX_OPTIONS

      message = Message.transaction { create_poll_message(room, question, options) }

      room.publish_message(message.reload)
      render json: message.as_chat_json(viewer: current_user), status: :created
    end

    # POST /api/polls/:id/votes { option_ids: [] }
    # Голос отдаётся один раз: вместе с ним открываются результаты, и переголосование
    # превратило бы опрос в гонку за большинством. В опросе с несколькими ответами
    # присланный набор и есть весь выбор участника.
    def vote
      poll = accessible_poll
      return render json: {error: "not_found"}, status: :not_found unless poll
      return render json: {error: "poll_closed"}, status: :unprocessable_entity if poll.closed?
      return render json: {error: "already_voted"}, status: :unprocessable_entity if poll.voted_by?(current_user)
      return render json: {error: "rate_limited"}, status: :too_many_requests unless allow_vote?

      option_ids = requested_option_ids(poll)
      return render json: {error: "options_required"}, status: :unprocessable_entity if option_ids.empty?
      return render json: {error: "single_choice_only"}, status: :unprocessable_entity if !poll.multiple && option_ids.size > 1

      Poll.transaction do
        option_ids.each { |option_id| poll.poll_votes.create!(user: current_user, poll_option_id: option_id) }
      end

      broadcast_poll(poll)
      render json: poll.reload.as_chat_json(viewer: current_user)
    end

    # POST /api/polls/:id/close — закрытый опрос показывает результаты, но голосовать в нём нельзя.
    def close
      poll = accessible_poll
      return render json: {error: "not_found"}, status: :not_found unless poll
      return render json: {error: "forbidden"}, status: :forbidden unless poll.owned_by?(current_user)

      poll.update!(closed_at: Time.current) unless poll.closed?
      broadcast_poll(poll)
      render json: poll.reload.as_chat_json(viewer: current_user)
    end

    private

    # Опрос доступен тому, кому доступно его сообщение: комнаты чужих опросов нам не принадлежат.
    def accessible_poll
      Poll.joins(:message).where(messages: {room_id: current_user.rooms.select(:id), deleted_at: nil}).find_by(id: params[:id])
    end

    def create_poll_message(room, question, options)
      message = room.messages.create!(user: current_user, body: "")
      poll = message.create_poll!(question: question, multiple: multiple?)
      options.each_with_index { |text, index| poll.poll_options.create!(text: text, position: index) }
      message
    end

    # Свежие результаты уходят всей комнате: у голосующего они меняются оптимистично,
    # остальные видят их только по этому кадру.
    def broadcast_poll(poll)
      message = poll.message.reload
      message.room.broadcast_message(message)
    end

    def multiple?
      ActiveModel::Type::Boolean.new.cast(params[:multiple]) || false
    end

    def poll_options
      Array(params[:options]).filter_map { |option| normalized_text(option, Poll::MAX_OPTION_LENGTH) }.uniq
    end

    # Варианты и вопрос — простой текст: разметка в них не рисуется, а санитайзер сообщения
    # к ним не применяется, поэтому чистим сами.
    def normalized_text(value, limit)
      text = Message.plain_text_from_html(value.to_s).delete("<>")

      text.presence&.truncate(limit)
    end

    def requested_option_ids(poll)
      ids = Array(params[:option_ids]).map(&:to_i).uniq

      poll.poll_options.where(id: ids).pluck(:id)
    end

    def allow_create?
      ChatRateLimiter.allow?("poll_create:#{current_user.id}", **ChatLimits.rate(:poll_create))
    end

    def allow_vote?
      ChatRateLimiter.allow?("poll_vote:#{current_user.id}", **ChatLimits.rate(:poll_vote))
    end

    def render_chat_blocked
      render json: {error: "direct_chat_blocked"}, status: :forbidden
    end
  end
end
