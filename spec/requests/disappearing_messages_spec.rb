# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Disappearing and one-time messages" do
  def identity(user)
    {external_id: user.external_id, name: user.name}
  end

  def group_with(*users)
    Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
  end

  def history(user, room)
    get "/api/rooms/#{room.id}/messages", params: identity(user)
    response.parsed_body
  end

  describe "room TTL" do
    it "stamps new messages with the room deadline and leaves older ones alone" do
      user = create(:user)
      room = group_with(user, create(:user))
      old = create(:message, room: room, user: user)

      patch "/api/rooms/#{room.id}/ttl", params: identity(user).merge(ttl_seconds: 300)
      fresh = create(:message, room: room.reload, user: user)

      expect(response).to have_http_status(:ok), response.body
      expect(old.reload.expires_at).to be_nil
      expect(fresh.expires_at).to be_within(5.seconds).of(5.minutes.from_now)
    end

    it "refuses a deadline outside the offered options" do
      user = create(:user)
      room = group_with(user, create(:user))

      patch "/api/rooms/#{room.id}/ttl", params: identity(user).merge(ttl_seconds: 7)

      expect(response).to have_http_status(:unprocessable_content)
      expect(room.reload.ttl_seconds).to be_nil
    end

    it "hides an expired message from the history even if its job never ran" do
      user = create(:user)
      room = group_with(user, create(:user))
      expired = create(:message, room: room, user: user, expires_at: 1.minute.ago)

      messages = history(user, room).fetch("messages")

      expect(messages).to be_empty
      expect(expired.reload).to be_deleted
    end
  end

  describe "view once" do
    it "does not send the content to the recipient until they open it" do
      author = create(:user)
      recipient = create(:user)
      room = group_with(author, recipient)
      post "/api/rooms/#{room.id}/messages", params: identity(author).merge(body: "секрет", view_once: true)

      sealed = history(recipient, room).fetch("messages").first

      expect(sealed.fetch("view_once")).to be(true)
      expect(sealed.fetch("body")).to eq("")
    end

    it "reveals the content once and refuses the second attempt" do
      author = create(:user)
      recipient = create(:user)
      room = group_with(author, recipient)
      post "/api/rooms/#{room.id}/messages", params: identity(author).merge(body: "секрет", view_once: true)
      message_id = response.parsed_body.fetch("id")

      post "/api/messages/#{message_id}/view", params: identity(recipient)
      revealed = response.parsed_body
      post "/api/messages/#{message_id}/view", params: identity(recipient)

      expect(revealed.fetch("body")).to include("секрет")
      expect(response).to have_http_status(:gone)
      expect(history(recipient, room).fetch("messages").first.fetch("body")).to eq("")
    end

    it "keeps the content visible for its own author" do
      author = create(:user)
      room = group_with(author, create(:user))
      post "/api/rooms/#{room.id}/messages", params: identity(author).merge(body: "секрет", view_once: true)

      own = history(author, room).fetch("messages").first

      expect(own.fetch("body")).to include("секрет")
      expect(own.fetch("view_once_viewers_count")).to be_zero
    end

    it "does not leak the content through the chat list preview" do
      author = create(:user)
      recipient = create(:user)
      room = group_with(author, recipient)
      post "/api/rooms/#{room.id}/messages", params: identity(author).merge(body: "секрет", view_once: true)

      get "/api/rooms", params: identity(recipient)

      expect(response.parsed_body.first.dig("last_message", "body")).to eq("Одноразовое сообщение")
    end
  end
end
