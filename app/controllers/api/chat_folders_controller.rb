# frozen_string_literal: true

module Api
  # Папки чатов — личные вкладки над списком диалогов. Состав хранится ссылками на комнаты,
  # поэтому чат, из которого человек вышел, пропадает из папки сам.
  class ChatFoldersController < BaseController
    # GET /api/chat_folders
    def index
      render json: {folders: current_user.chat_folders.includes(:rooms).map(&:as_chat_json)}
    end

    # POST /api/chat_folders { title:, room_ids: [] }
    # Имя папки приходит как title: параметр name занят под личность вызывающего.
    def create
      name = folder_name
      return render json: {error: "title_required"}, status: :unprocessable_entity if name.blank?

      if current_user.chat_folders.count >= ChatFolder::MAX_FOLDERS_PER_USER
        return render json: {error: "too_many_folders"}, status: :unprocessable_entity
      end

      folder = current_user.chat_folders.create!(name: name, position: next_position)
      replace_rooms(folder) if params.key?(:room_ids)

      render json: folder.reload.as_chat_json, status: :created
    end

    # PATCH /api/chat_folders/:id { title:, room_ids: [] }
    # Переданы только меняющиеся поля: без room_ids состав папки остаётся прежним.
    def update
      folder = current_user.chat_folders.find(params[:id])

      if params.key?(:title)
        name = folder_name
        return render json: {error: "title_required"}, status: :unprocessable_entity if name.blank?

        folder.update!(name: name)
      end

      replace_rooms(folder) if params.key?(:room_ids)
      render json: folder.reload.as_chat_json
    end

    # DELETE /api/chat_folders/:id — уносит только вкладку, сами чаты остаются на месте.
    def destroy
      current_user.chat_folders.find(params[:id]).destroy!
      head :no_content
    end

    private

    def folder_name
      params[:title].to_s.squish.truncate(ChatFolder::MAX_NAME_LENGTH).presence
    end

    # Позиция новой вкладки — в конец: порядок задаёт владелец, а не алфавит.
    def next_position
      (current_user.chat_folders.maximum(:position) || -1) + 1
    end

    # В папку кладём только свои комнаты: id приходят от клиента, и чужой чат по ним
    # не должен попадать даже в личную вкладку.
    def replace_rooms(folder)
      ids = Array(params[:room_ids]).map(&:to_i).uniq.first(ChatFolder::MAX_ROOMS_PER_FOLDER)
      allowed = current_user.rooms.where(id: ids).pluck(:id)

      folder.chat_folder_rooms.where.not(room_id: allowed).destroy_all
      (allowed - folder.chat_folder_rooms.pluck(:room_id)).each do |room_id|
        folder.chat_folder_rooms.create!(room_id: room_id)
      end
    end
  end
end
