# frozen_string_literal: true

module Api
  # Вкладка «Медиа» диалога: всё вложенное и все ссылки комнаты одним списком —
  # прокруткой треда такое не ищут.
  class AttachmentsController < BaseController
    LIMIT = 200

    # GET /api/rooms/:room_id/attachments
    def index
      room = current_user.rooms.find(params[:room_id])

      render json: {
        attachments: room_attachments(room).reject { |attachment| attachment.message.hidden_from?(current_user) }
                                  .map { |attachment| attachment_json(attachment) },
        links: room_links(room)
      }
    end

    private

    def room_attachments(room)
      MessageAttachment
        .joins(:message)
        .where(messages: {room_id: room.id, deleted_at: nil})
        .includes(message: :user)
        .order(id: :desc)
        .limit(LIMIT)
    end

    # К вложению добавляем контекст сообщения: из вкладки по нему прыгают в тред.
    def attachment_json(attachment)
      attachment.as_chat_json.merge(
        message_id: attachment.message_id,
        created_at: attachment.message.created_at.iso8601,
        author_name: attachment.message.user.name
      )
    end

    # Отдельной таблицы под ссылки нет — достаём их из тела: и оформленные, и набранные текстом.
    def room_links(room)
      messages = room.messages.visible.where("messages.plain_body LIKE ? OR messages.body LIKE ?", "%http%", "%<a %")
                     .includes(:user).order(id: :desc).limit(LIMIT)

      messages.reject { |message| message.hidden_from?(current_user) }
              .flat_map { |message| message_links(message) }
    end

    def message_links(message)
      message.links.map do |url|
        {
          message_id: message.id,
          created_at: message.created_at.iso8601,
          author_name: message.user.name,
          url: url,
          # Карточка есть только у первой ссылки сообщения — её и разворачивает джоба.
          preview: url == message.first_link ? message.parsed_link_preview : nil
        }
      end
    end
  end
end
