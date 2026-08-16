# frozen_string_literal: true

module Api
  # Приглашение в группу по ссылке. Токен вместо id комнаты: по id ссылку подобрали бы
  # перебором, а отозвать приглашение было бы нечем.
  class InvitesController < BaseController
    # POST /api/rooms/:id/invite — создаёт ссылку или возвращает уже выданную.
    def create
      room = current_user.rooms.find(params[:id])
      return render json: {error: "not_a_group"}, status: :unprocessable_entity unless invitable?(room)
      return render json: {error: "forbidden"}, status: :forbidden unless room.owned_by?(current_user)

      render json: invite_json(room, room.ensure_invite_token!), status: :created
    end

    # DELETE /api/rooms/:id/invite — старая ссылка перестаёт работать сразу.
    def destroy
      room = current_user.rooms.find(params[:id])
      return render json: {error: "forbidden"}, status: :forbidden unless room.owned_by?(current_user)

      room.revoke_invite_token!
      head :no_content
    end

    # GET /api/invites/:token — что за группа за ссылкой, до вступления в неё.
    def show
      room = invited_room
      return render json: {error: "invite_not_found"}, status: :not_found unless room

      render json: {
        room_id: room.id,
        name: room.name,
        avatar_url: room.avatar_image_url,
        members_count: room.users.count,
        # Уже состоящему в группе кнопка предложит просто открыть чат, а не вступать заново.
        joined: room.room_memberships.exists?(user_id: current_user.id)
      }
    end

    # POST /api/invites/:token/join
    def join
      room = invited_room
      return render json: {error: "invite_not_found"}, status: :not_found unless room
      return render json: {error: "rate_limited"}, status: :too_many_requests unless allow_join?
      if room.users.count >= RoomsController::MAX_GROUP_MEMBERS
        return render json: {error: "too_many_members"}, status: :unprocessable_entity
      end

      room.add_member(current_user)
      # Список чатов обновляется и у вступившего, и у тех, кто уже в группе: состав изменился.
      room.reload.notify_activity
      render json: {room_id: room.id}, status: :created
    end

    private

    def invited_room
      token = params[:token].to_s
      return if token.blank?

      Room.find_by(invite_token: token)
    end

    # Ссылку заводим только группе: у лички состав фиксирован двумя людьми, а «Избранное» —
    # личная комната одного человека.
    def invitable?(room)
      room.group? && !room.channel?
    end

    def invite_json(room, token)
      {room_id: room.id, token: token}
    end

    def allow_join?
      ChatRateLimiter.allow?("invite_join:#{current_user.id}", **ChatLimits.rate(:invite_join))
    end
  end
end
