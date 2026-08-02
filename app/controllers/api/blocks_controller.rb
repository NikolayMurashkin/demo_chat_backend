# frozen_string_literal: true

module Api
  class BlocksController < BaseController
    before_action :set_room

    # POST /api/rooms/:room_id/block — блокирует личную переписку в обе стороны до разблокировки.
    def create
      peer = direct_peer
      return unless peer

      # create_or_find_by! вместо find_or_create_by!: повторный клик из двух вкладок иначе
      # ловит нарушение уникального индекса вместо того, чтобы просто вернуть существующую запись.
      UserBlock.create_or_find_by!(blocker: current_user, blocked: peer)
      notify_block_change
      render json: {block_state: "blocked_by_me"}, status: :created
    end

    # DELETE /api/rooms/:room_id/block — снять только свою блокировку.
    def destroy
      peer = direct_peer
      return unless peer

      UserBlock.find_by(blocker: current_user, blocked: peer)&.destroy!
      notify_block_change
      render json: {block_state: @room.block_state_for(current_user)}
    end

    private

    def set_room
      @room = current_user.rooms.find(params[:id])
    end

    def direct_peer
      unless @room.direct?
        render json: {error: "not_a_direct_room"}, status: :unprocessable_entity
        return nil
      end

      peer = @room.peer_for(current_user)
      unless peer
        render json: {error: "peer_not_found"}, status: :unprocessable_entity
        return nil
      end

      peer
    end

    # Блокировка меняет права сразу у обеих сторон, а не только у того, кто её поставил:
    # у собеседника пропадает composer, поэтому событие уходит каждому участнику лички.
    def notify_block_change
      @room.notify_activity
      @room.users.find_each { |member| UserChannel.broadcast_to(member, {type: "blocks_changed", room_id: @room.id}) }
    end
  end
end
