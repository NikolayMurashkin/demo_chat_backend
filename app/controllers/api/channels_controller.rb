# frozen_string_literal: true

module Api
  # Каналы внутри группы — как в Discord: одна и та же компания, но разговоры разложены
  # по темам. Технически канал — обычная комната с родителем; состав он наследует.
  class ChannelsController < BaseController
    # POST /api/rooms/:id/channels { title: }
    def create
      parent = current_user.rooms.find(params[:id])
      return render json: {error: "not_a_group"}, status: :unprocessable_entity if !parent.group? || parent.channel?
      return render json: {error: "forbidden"}, status: :forbidden unless parent.owned_by?(current_user)

      title = params[:title].to_s.squish.presence
      return render json: {error: "title_required"}, status: :unprocessable_entity unless title
      if title.length > RoomsController::MAX_ROOM_NAME_LENGTH
        return render json: {error: "title_too_long"}, status: :unprocessable_entity
      end
      return render json: {error: "too_many_channels"}, status: :unprocessable_entity if parent.channels.count >= Room::MAX_CHANNELS

      channel = Room.create!(name: title, owner: parent.owner, parent: parent)
      # Состав канала повторяет состав группы: отдельного приглашения в него не существует.
      parent.users.each { |member| channel.add_member(member) }

      channel.reload.notify_activity
      render json: {id: channel.id, name: channel.name, parent_id: parent.id}, status: :created
    end
  end
end
