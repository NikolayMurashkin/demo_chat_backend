# frozen_string_literal: true

module Api
  class MembersController < BaseController
    before_action :set_room

    # POST /api/rooms/:room_id/members { members: [{ external_id:, name: }] }
    # Приглашение в групповой чат: звать может любой участник.
    def create
      return render json: {error: "not_a_group"}, status: :unprocessable_entity unless @room.group?
      requested = Array(params[:members])
      return render json: {error: "too_many_members"}, status: :unprocessable_entity if requested.size > RoomsController::MAX_GROUP_MEMBERS

      existing_ids = @room.user_ids
      invited = upsert_members(requested).uniq(&:id).reject { |member| existing_ids.include?(member.id) }
      return render json: {error: "members_required"}, status: :unprocessable_entity if invited.empty?
      return render json: {error: "group_full"}, status: :unprocessable_entity if existing_ids.size + invited.size > RoomsController::MAX_GROUP_MEMBERS

      invited.each { |member| @room.add_member(member) }
      @room.reload.notify_activity
      render json: {members: @room.users.map { |user| member_json(user) }}, status: :created
    end

    # DELETE /api/rooms/:room_id/members/:member_external_id — исключить участника (только создатель группы).
    def destroy
      return render json: {error: "not_a_group"}, status: :unprocessable_entity unless @room.group?
      return render json: {error: "forbidden"}, status: :forbidden unless @room.owned_by?(current_user)

      member = @room.users.find_by(external_id: params[:member_external_id])
      return render json: {error: "not_found"}, status: :not_found if member.nil?
      # Создатель уходит из группы только сам — иначе она осталась бы без владельца.
      return render json: {error: "cannot_remove_owner"}, status: :unprocessable_entity if member.id == @room.owner_id

      @room.membership_for(member)&.destroy
      # Исключённому список чатов надо обновить: в составе комнаты его больше нет,
      # и notify_activity до него уже не дойдёт.
      Room.notify_rooms_changed(member)
      @room.reload.notify_activity

      render json: {members: @room.users.map { |user| member_json(user) }}
    end

    private

    def set_room
      @room = current_user.rooms.find(params[:room_id])
    end
  end
end
