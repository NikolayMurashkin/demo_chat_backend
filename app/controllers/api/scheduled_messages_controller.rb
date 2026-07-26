# frozen_string_literal: true

module Api
  class ScheduledMessagesController < BaseController
    MAX_SCHEDULE_AHEAD = 30.days
    MAX_BODY_LENGTH = 10_000
    # Каждое отложенное сообщение — это ещё и джоба, живущая в памяти процесса до срока.
    # Без потолка их можно наплодить столько, сколько пропустит общий лимит запросов.
    MAX_PENDING_PER_ROOM = 20

    # GET /api/rooms/:room_id/scheduled_messages
    def index
      room = current_user.rooms.find(params[:room_id])
      scheduled = room.scheduled_messages.pending.where(user: current_user).order(:deliver_at)

      render json: {messages: scheduled.map { |message| scheduled_json(message) }}
    end

    # POST /api/rooms/:room_id/scheduled_messages
    def create
      room = current_user.rooms.find(params[:room_id])
      return render_chat_blocked if room.direct_chat_blocked_for?(current_user)
      body = normalized_body(params[:body])
      deliver_at = parsed_delivery_time(params[:deliver_at])

      return if invalid_body?(body) || invalid_delivery_time?(deliver_at)

      if room.scheduled_messages.pending.where(user: current_user).count >= MAX_PENDING_PER_ROOM
        return render json: {error: "too_many_scheduled_messages"}, status: :unprocessable_entity
      end

      scheduled = room.scheduled_messages.create!(user: current_user, body: body, deliver_at: deliver_at)
      enqueue_delivery(scheduled)
      render json: scheduled_json(scheduled), status: :created
    rescue ArgumentError
      render json: {error: "invalid_delivery_time"}, status: :unprocessable_entity
    end

    # PATCH /api/rooms/:room_id/scheduled_messages/:id
    def update
      room = current_user.rooms.find(params[:room_id])
      return render_chat_blocked if room.direct_chat_blocked_for?(current_user)
      scheduled = room.scheduled_messages.pending.find_by!(id: params[:id], user: current_user)
      attributes = update_attributes

      return if attributes.nil?

      scheduled.update!(attributes)
      enqueue_delivery(scheduled) if attributes.key?(:deliver_at)
      render json: scheduled_json(scheduled)
    rescue ArgumentError
      render json: {error: "invalid_delivery_time"}, status: :unprocessable_entity
    end

    # DELETE /api/rooms/:room_id/scheduled_messages/:id — job останется в очереди, но увидит cancelled_at.
    def destroy
      room = current_user.rooms.find(params[:room_id])
      scheduled = room.scheduled_messages.pending.find_by!(id: params[:id], user: current_user)
      scheduled.update!(cancelled_at: Time.current)
      head :no_content
    end

    private

    def render_chat_blocked
      render json: {error: "direct_chat_blocked"}, status: :forbidden
    end

    def update_attributes
      attributes = {}
      if params.key?(:body)
        body = normalized_body(params[:body])
        return nil if invalid_body?(body)

        attributes[:body] = body
      end
      if params.key?(:deliver_at)
        deliver_at = parsed_delivery_time(params[:deliver_at])
        return nil if invalid_delivery_time?(deliver_at)

        attributes[:deliver_at] = deliver_at
      end

      attributes
    end

    def normalized_body(body)
      Message.normalized_body(body)
    end

    def parsed_delivery_time(deliver_at)
      Time.iso8601(deliver_at.to_s)
    end

    def invalid_body?(body)
      if body.blank?
        render json: {error: "empty_message"}, status: :unprocessable_entity
        true
      elsif body.length > MAX_BODY_LENGTH
        render json: {error: "message_too_long"}, status: :unprocessable_entity
        true
      else
        false
      end
    end

    def invalid_delivery_time?(deliver_at)
      if deliver_at <= 1.minute.from_now
        render json: {error: "delivery_time_too_soon"}, status: :unprocessable_entity
        true
      elsif deliver_at > MAX_SCHEDULE_AHEAD.from_now
        render json: {error: "delivery_time_too_far"}, status: :unprocessable_entity
        true
      else
        false
      end
    end

    def enqueue_delivery(scheduled)
      DeliverScheduledMessageJob.set(wait_until: scheduled.deliver_at).perform_later(scheduled.id)
    end

    def scheduled_json(scheduled)
      {id: scheduled.id, room_id: scheduled.room_id, body: scheduled.body, deliver_at: scheduled.deliver_at.iso8601}
    end
  end
end
