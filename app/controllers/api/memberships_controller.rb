# frozen_string_literal: true

module Api
  # Личные настройки чата: приглушение, закрепление в списке и ручная пометка «непрочитано».
  # Все три живут на связи участник↔комната, поэтому одна ручка вместо трёх.
  class MembershipsController < BaseController
    FLAGS = {muted: :muted_at, pinned: :pinned_at, marked_unread: :marked_unread_at, archived: :archived_at}.freeze

    # PATCH /api/rooms/:room_id/membership { muted:, pinned:, marked_unread:, archived:, theme: }
    # Переданы только меняющиеся флаги: отсутствующий параметр оставляет настройку как есть.
    def update
      room = current_user.rooms.find(params[:room_id])
      membership = room.membership_for(current_user)
      return render json: {error: "not_found"}, status: :not_found unless membership

      FLAGS.each do |param, column|
        next unless params.key?(param)

        membership[column] = ActiveModel::Type::Boolean.new.cast(params[param]) ? Time.current : nil
      end

      if params.key?(:theme)
        theme = params[:theme].to_s
        return render json: {error: "invalid_theme"}, status: :unprocessable_entity unless RoomMembership::THEMES.include?(theme)

        membership.theme = theme
      end

      membership.save!

      # Список чатов перестраивается на других вкладках того же пользователя: закрепление
      # меняет порядок, приглушение — колокольчик, пометка — точку непрочитанного.
      room.notify_activity(only: current_user)
      render json: membership_json(membership)
    end

    private

    def membership_json(membership)
      {
        room_id: membership.room_id,
        muted: membership.muted?,
        pinned: membership.pinned?,
        marked_unread: membership.marked_unread?,
        archived: membership.archived?,
        theme: membership.theme_name
      }
    end
  end
end
