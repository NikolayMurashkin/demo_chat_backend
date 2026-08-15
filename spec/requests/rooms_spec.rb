# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chat rooms" do
  def text_upload
    fixture_file_upload(Rails.root.join("spec/fixtures/files/note.txt"), "text/plain")
  end

  describe "POST /api/rooms" do
    it "does not create a one-person direct message" do
      user = create(:user)

      expect {
        post "/api/rooms", params: {
          external_id: user.external_id,
          name: user.name,
          target_external_id: user.external_id,
          target_name: user.name
        }
      }.not_to change(Room, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({"error" => "cannot_message_self"})
    end

    it "keeps a new empty direct message hidden from the recipient until the first message" do
      sender = create(:user)
      recipient = create(:user)

      post "/api/rooms", params: {
        external_id: sender.external_id,
        name: sender.name,
        target_external_id: recipient.external_id,
        target_name: recipient.name
      }

      room_id = response.parsed_body.fetch("id")
      expect(response).to have_http_status(:created)
      expect(Room.find(room_id).membership_for(sender)).to be_visible
      expect(Room.find(room_id).membership_for(recipient)).not_to be_visible

      get "/api/rooms", params: {external_id: recipient.external_id, name: recipient.name}
      expect(response.parsed_body).to be_empty

      post "/api/rooms/#{room_id}/messages", params: {
        external_id: sender.external_id,
        name: sender.name,
        body: "Привет"
      }

      expect(response).to have_http_status(:created)

      get "/api/rooms", params: {external_id: recipient.external_id, name: recipient.name}
      expect(response.parsed_body.map { |room| room.fetch("id") }).to include(room_id)
    end
  end

  describe "POST /api/rooms/group" do
    it "rejects a title that is blank after whitespace is normalized" do
      user = create(:user)

      expect {
        post "/api/rooms/group", params: {external_id: user.external_id, name: user.name, title: " \n "}
      }.not_to change(Room, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({"error" => "title_required"})
    end
  end

  describe "POST /api/rooms/saved" do
    it "returns one personal saved room for the current user" do
      user = create(:user)

      post "/api/rooms/saved", params: {external_id: user.external_id, name: user.name}

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body).to include("name" => "Избранное", "is_group" => false, "is_saved" => true)

      post "/api/rooms/saved", params: {external_id: user.external_id, name: user.name}

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body.fetch("id")).to eq(Room.find_by(saved_for: user).id)
      expect(Room.where(saved_for: user).count).to eq(1)
    end
  end

  describe "GET /api/rooms" do
    it "returns the latest preview and correct unread count" do
      recipient = create(:user)
      author = create(:user)
      room = create(:room)
      room.add_member(recipient)
      room.add_member(author)
      create(:message, room: room, user: author, body: "First")
      latest = create(:message, room: room, user: author, body: "Latest")

      get "/api/rooms", params: {external_id: recipient.external_id, name: recipient.name}

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        a_hash_including(
          "id" => room.id,
          "unread_count" => 2,
          "last_message" => a_hash_including("body" => latest.preview_text, "author" => author.name)
        )
      )
    end
  end

  describe "GET /api/rooms/:id" do
    # Одну комнату и список комнат считают разные запросы; расхождение в них выглядело бы
    # как бейдж, который зовёт в чат, где показывать уже нечего.
    it "counts unread the same way as the dialog list: no deleted and no hidden authors" do
      reader = create(:user)
      author = create(:user)
      blocked_author = create(:user)
      room = create(:room)
      [reader, author, blocked_author].each { |member| room.add_member(member) }
      UserBlock.create!(blocker: reader, blocked: blocked_author)
      create(:message, room: room, user: author, body: "Видно")
      create(:message, room: room, user: blocked_author, body: "Скрыто")
      create(:message, room: room, user: author, body: "Удалено").soft_delete!

      get "/api/rooms/#{room.id}", params: {external_id: reader.external_id, name: reader.name}
      expect(response.parsed_body.fetch("unread_count")).to eq(1)

      get "/api/rooms", params: {external_id: reader.external_id, name: reader.name}
      expect(response.parsed_body).to include(a_hash_including("id" => room.id, "unread_count" => 1))
    end
  end

  describe "GET /api/rooms ordering" do
    it "puts the freshest conversation first and a still empty one above older talk" do
      user = create(:user)
      older = create(:room)
      newer = create(:room)
      empty = create(:room)
      [older, newer, empty].each { |room| room.add_member(user) }
      create(:message, room: older, user: user, created_at: 2.days.ago)
      create(:message, room: newer, user: user, created_at: 1.hour.ago)

      get "/api/rooms", params: {external_id: user.external_id, name: user.name}

      expect(response.parsed_body.map { |room| room.fetch("id") }).to eq([empty.id, newer.id, older.id])
    end
  end

  describe "POST /api/rooms/:room_id/messages" do
    it "accepts an attachment-only message" do
      sender = create(:user)
      room = create(:room)
      room.add_member(sender)
      upload = text_upload

      post "/api/rooms/#{room.id}/messages", params: {
        external_id: sender.external_id,
        name: sender.name,
        files: [upload]
      }

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body.fetch("attachments")).to have_attributes(size: 1)
    end

    it "adds a reply to a separate discussion without putting it in the room timeline" do
      sender = create(:user)
      room = create(:room)
      room.add_member(sender)
      root = create(:message, room: room, user: sender, body: "Давайте обсудим")

      post "/api/rooms/#{room.id}/messages", params: {
        external_id: sender.external_id,
        name: sender.name,
        body: "Поддерживаю",
        thread_root_id: root.id
      }

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body).to include("thread_root_id" => root.id, "thread_reply_count" => 1)

      get "/api/rooms/#{room.id}/messages", params: {external_id: sender.external_id, name: sender.name}

      expect(response.parsed_body.fetch("messages").map { |message| message.fetch("id") }).to eq([root.id])
    end

    it "returns the root and replies of a discussion to room members only" do
      sender = create(:user)
      room = create(:room)
      room.add_member(sender)
      root = create(:message, room: room, user: sender, body: "Тема")
      reply = create(:message, room: room, user: sender, body: "Ответ", thread_root: root)

      get "/api/rooms/#{room.id}/messages/#{root.id}/thread", params: {
        external_id: sender.external_id,
        name: sender.name
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch("root")).to include("id" => root.id, "thread_reply_count" => 1)
      expect(response.parsed_body.fetch("messages").map { |message| message.fetch("id") }).to eq([reply.id])
    end
  end

  describe "POST /api/messages/:id/save" do
    it "copies a message and its attachments to the user's saved room" do
      sender = create(:user)
      room = create(:room)
      room.add_member(sender)
      source = create(:message, room: room, user: sender, body: "Полезная ссылка")

      post "/api/messages/#{source.id}/save", params: {external_id: sender.external_id, name: sender.name}

      expect(response).to have_http_status(:created), response.body
      saved_room = Room.find(response.parsed_body.fetch("saved_room_id"))
      expect(saved_room).to be_saved
      expect(saved_room.messages.last).to have_attributes(body: source.body, forwarded_from_name: sender.name)
    end
  end

  describe "POST /api/rooms/:room_id/scheduled_messages" do
    it "creates a scheduled message, lets its author edit it, then cancel it" do
      sender = create(:user)
      room = create(:room)
      room.add_member(sender)

      post "/api/rooms/#{room.id}/scheduled_messages", params: {
        external_id: sender.external_id,
        name: sender.name,
        body: "Напомнить через десять минут",
        deliver_at: 10.minutes.from_now.iso8601
      }

      expect(response).to have_http_status(:created), response.body
      scheduled_id = response.parsed_body.fetch("id")

      get "/api/rooms/#{room.id}/scheduled_messages", params: {
        external_id: sender.external_id,
        name: sender.name
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch("messages").map { |message| message.fetch("id") }).to eq([scheduled_id])

      patch "/api/rooms/#{room.id}/scheduled_messages/#{scheduled_id}", params: {
        external_id: sender.external_id,
        name: sender.name,
        body: "Напомнить через двадцать минут",
        deliver_at: 20.minutes.from_now.iso8601
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body).to include("body" => "Напомнить через двадцать минут")
      expect(ScheduledMessage.find(scheduled_id).deliver_at).to be_within(1.second).of(20.minutes.from_now)

      delete "/api/rooms/#{room.id}/scheduled_messages/#{scheduled_id}", params: {
        external_id: sender.external_id,
        name: sender.name
      }

      expect(response).to have_http_status(:no_content)
      expect(ScheduledMessage.find(scheduled_id).cancelled_at).to be_present
    end
  end

  describe "DELETE /api/rooms/:id" do
    it "tells the leaver's own other tabs that the group is gone" do
      owner = create(:user)
      leaver = create(:user)
      room = Room.create!(name: "Команда", owner: owner)
      room.add_member(owner)
      room.add_member(leaver)

      expect {
        delete "/api/rooms/#{room.id}", params: {external_id: leaver.external_id, name: leaver.name}
      }.to have_broadcasted_to(leaver).from_channel(UserChannel).with(hash_including(type: "rooms_changed"))

      expect(response).to have_http_status(:no_content)
      expect(room.reload.users).not_to include(leaver)
    end

    it "does not bring a deleted direct chat back to the peer just because the other side reopened it" do
      sender = create(:user)
      recipient = create(:user)
      room = Room.create!(dm_key: "dm:#{[sender.id, recipient.id].sort.join('-')}")
      room.add_member(sender)
      room.add_member(recipient)
      create(:message, room: room, user: sender, body: "Привет")

      delete "/api/rooms/#{room.id}", params: {external_id: recipient.external_id, name: recipient.name}
      expect(response).to have_http_status(:no_content)

      post "/api/rooms", params: {
        external_id: sender.external_id,
        name: sender.name,
        target_external_id: recipient.external_id,
        target_name: recipient.name
      }

      expect(response).to have_http_status(:created), response.body
      expect(room.membership_for(recipient)).not_to be_visible

      post "/api/rooms/#{room.id}/messages", params: {
        external_id: sender.external_id, name: sender.name, body: "Ещё раз привет"
      }

      expect(response).to have_http_status(:created), response.body
      expect(room.membership_for(recipient).reload).to be_visible
    end
  end

  describe "GET /api/rooms/:room_id/messages" do
    it "answers with an empty page instead of failing when a cursor is not a message id" do
      user = create(:user)
      room = create(:room)
      room.add_member(user)
      create(:message, room: room, user: user)

      get "/api/rooms/#{room.id}/messages", params: {
        external_id: user.external_id, name: user.name, before: "not-a-cursor"
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch("messages")).to have_attributes(size: 1)
    end
  end

  describe "POST /api/messages/forward" do
    it "refuses a forward that would fan out into more copies than a person sends by hand" do
      sender = create(:user)
      source_room = create(:room)
      source_room.add_member(sender)
      messages = Array.new(4) { create(:message, room: source_room, user: sender) }
      targets = Array.new(20) { create(:room).tap { |room| room.add_member(sender) } }

      expect {
        post "/api/messages/forward", params: {
          external_id: sender.external_id,
          name: sender.name,
          message_ids: messages.map(&:id),
          room_ids: targets.map(&:id)
        }
      }.not_to change(Message, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({"error" => "too_many_forward_copies"})
    end
  end
end
