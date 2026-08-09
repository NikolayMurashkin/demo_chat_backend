# frozen_string_literal: true

require "rails_helper"

# Всё, чем человек раскладывает свои чаты по местам: архив, папки, отметки «важное»,
# оформление и каналы внутри группы.
RSpec.describe "Chat organization" do
  def identity(user)
    {external_id: user.external_id, name: user.name}
  end

  def group_with(owner, *members)
    Room.create!(name: "Команда", owner: owner).tap do |room|
      room.add_member(owner)
      members.each { |member| room.add_member(member) }
    end
  end

  def room_summaries(user)
    get "/api/rooms", params: identity(user)
    response.parsed_body
  end

  describe "archive" do
    it "keeps an archived chat in the list with its unread counter" do
      user = create(:user)
      peer = create(:user)
      room = group_with(user, peer)
      create(:message, room: room, user: peer)

      patch "/api/rooms/#{room.id}/membership", params: identity(user).merge(archived: true)
      summary = room_summaries(user).first

      expect(summary.fetch("archived")).to be(true)
      expect(summary.fetch("unread_count")).to eq(1)
    end

    it "archives the chat only for the participant who asked" do
      user = create(:user)
      peer = create(:user)
      room = group_with(user, peer)

      patch "/api/rooms/#{room.id}/membership", params: identity(user).merge(archived: true)

      expect(room_summaries(peer).first.fetch("archived")).to be(false)
    end
  end

  describe "theme" do
    it "stores the chat appearance per participant" do
      user = create(:user)
      peer = create(:user)
      room = group_with(user, peer)

      patch "/api/rooms/#{room.id}/membership", params: identity(user).merge(theme: "forest")

      expect(response.parsed_body.fetch("theme")).to eq("forest")
      expect(room_summaries(peer).first.fetch("theme")).to eq("classic")
    end

    it "refuses an unknown appearance" do
      user = create(:user)
      room = group_with(user, create(:user))

      patch "/api/rooms/#{room.id}/membership", params: identity(user).merge(theme: "<script>")

      expect(response).to have_http_status(:unprocessable_content)
      expect(room.membership_for(user).theme).to be_nil
    end
  end

  describe "starred messages" do
    it "collects starred messages from different chats with their room names" do
      user = create(:user)
      first = group_with(user, create(:user))
      second = group_with(user, create(:user))
      messages = [create(:message, room: first, user: user), create(:message, room: second, user: user)]

      messages.each { |message| post "/api/messages/#{message.id}/star", params: identity(user) }
      get "/api/starred_messages", params: identity(user)

      expect(response.parsed_body.fetch("messages").map { |message| message.dig("room", "id") })
        .to contain_exactly(first.id, second.id)
    end

    it "keeps the mark personal" do
      user = create(:user)
      peer = create(:user)
      room = group_with(user, peer)
      message = create(:message, room: room, user: user)

      post "/api/messages/#{message.id}/star", params: identity(user)
      get "/api/starred_messages", params: identity(peer)

      expect(response.parsed_body.fetch("messages")).to be_empty
    end

    it "refuses to star a message from a room the user does not belong to" do
      outsider = create(:user)
      room = group_with(create(:user), create(:user))
      message = create(:message, room: room, user: room.users.first)

      post "/api/messages/#{message.id}/star", params: identity(outsider)

      expect(response).to have_http_status(:not_found)
      expect(StarredMessage.count).to be_zero
    end
  end

  describe "folders" do
    it "only accepts rooms the owner belongs to" do
      user = create(:user)
      own = group_with(user, create(:user))
      foreign = group_with(create(:user), create(:user))

      post "/api/chat_folders", params: identity(user).merge(title: "Работа", room_ids: [own.id, foreign.id])

      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body.fetch("room_ids")).to eq([own.id])
    end

    it "replaces the contents on update and leaves the name alone" do
      user = create(:user)
      first = group_with(user, create(:user))
      second = group_with(user, create(:user))
      post "/api/chat_folders", params: identity(user).merge(title: "Работа", room_ids: [first.id])
      folder_id = response.parsed_body.fetch("id")

      patch "/api/chat_folders/#{folder_id}", params: identity(user).merge(room_ids: [second.id])

      expect(response.parsed_body.fetch("room_ids")).to eq([second.id])
      expect(response.parsed_body.fetch("name")).to eq("Работа")
    end

    it "does not show one person's folders to another" do
      user = create(:user)
      post "/api/chat_folders", params: identity(user).merge(title: "Работа")

      get "/api/chat_folders", params: identity(create(:user))

      expect(response.parsed_body.fetch("folders")).to be_empty
    end
  end

  describe "channels" do
    it "gives the channel the whole group as its members and hides it from the chat list" do
      owner = create(:user)
      member = create(:user)
      group = group_with(owner, member)

      post "/api/rooms/#{group.id}/channels", params: identity(owner).merge(title: "релизы")
      channel = Room.find(response.parsed_body.fetch("id"))

      expect(channel.users).to contain_exactly(owner, member)
      # Канал остаётся в выдаче ради прямых ссылок и общего бейджа, но помечен как канал —
      # строкой левой панели его делать нельзя, он живёт вкладкой в шапке своей группы.
      expect(room_summaries(member).find { |room| room.fetch("id") == channel.id }).to include("is_channel" => true)
      expect(room_summaries(member).find { |room| room.fetch("id") == group.id }.fetch("channels")
        .map { |item| item.fetch("name") }).to eq(["релизы"])
    end

    it "adds a newcomer of the group to its channels" do
      owner = create(:user)
      group = group_with(owner)
      post "/api/rooms/#{group.id}/channels", params: identity(owner).merge(title: "релизы")
      newcomer = create(:user)

      post "/api/rooms/#{group.id}/members", params: identity(owner).merge(
        members: [{external_id: newcomer.external_id, name: newcomer.name}],
      )

      expect(group.reload.channels.first.users).to include(newcomer)
    end

    it "lets only the owner create a channel" do
      owner = create(:user)
      member = create(:user)
      group = group_with(owner, member)

      post "/api/rooms/#{group.id}/channels", params: identity(member).merge(title: "своё")

      expect(response).to have_http_status(:forbidden)
      expect(group.channels).to be_empty
    end
  end
end
