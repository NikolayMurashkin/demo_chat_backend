# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Direct chat blocks" do
  def direct_room(*users)
    room = Room.create!(dm_key: "dm:#{users.map(&:id).sort.join('-')}")
    users.each { |user| room.add_member(user) }
    room
  end

  it "keeps the direct room readable but blocks interaction for both participants until the blocker unblocks it" do
    blocker = create(:user)
    peer = create(:user)
    room = direct_room(blocker, peer)

    post "/api/rooms/#{room.id}/block", params: {external_id: blocker.external_id, name: blocker.name}

    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body).to eq({"block_state" => "blocked_by_me"})
    expect(UserBlock).to exist(blocker: blocker, blocked: peer)

    get "/api/rooms", params: {external_id: peer.external_id, name: peer.name}
    expect(response.parsed_body).to include(a_hash_including("id" => room.id, "block_state" => "blocked_me"))

    # Блокировка останавливает общение, но не должна превращать существующий диалог
    # в недоступный: оба участника могут открыть историю и увидеть кнопку разблокировки.
    [blocker, peer].each do |user|
      get "/api/rooms/#{room.id}/messages", params: {external_id: user.external_id, name: user.name}
      expect(response).to have_http_status(:ok), response.body

      get "/api/rooms/#{room.id}/scheduled_messages", params: {external_id: user.external_id, name: user.name}
      expect(response).to have_http_status(:ok), response.body
    end

    post "/api/rooms/#{room.id}/messages", params: {
      external_id: peer.external_id, name: peer.name, body: "Вы меня слышите?"
    }
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq({"error" => "direct_chat_blocked"})

    delete "/api/rooms/#{room.id}/block", params: {external_id: blocker.external_id, name: blocker.name}
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to eq({"block_state" => "none"})

    post "/api/rooms/#{room.id}/messages", params: {
      external_id: peer.external_id, name: peer.name, body: "Теперь можно писать"
    }
    expect(response).to have_http_status(:created), response.body
  end

  it "does not allow blocking a group room" do
    user = create(:user)
    room = create(:room)
    room.add_member(user)

    post "/api/rooms/#{room.id}/block", params: {external_id: user.external_id, name: user.name}

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq({"error" => "not_a_direct_room"})
  end

  it "returns a safe placeholder instead of a blocked participant's group message" do
    blocker = create(:user)
    blocked = create(:user)
    observer = create(:user)
    room = create(:room)
    [blocker, blocked, observer].each { |user| room.add_member(user) }
    message = create(:message, room: room, user: blocked, body: "Секретное сообщение")
    UserBlock.create!(blocker: blocker, blocked: blocked)

    get "/api/rooms/#{room.id}/messages", params: {external_id: blocker.external_id, name: blocker.name}
    hidden = response.parsed_body.fetch("messages").find { |item| item.fetch("id") == message.id }
    expect(hidden).to include("blocked" => true, "body" => "", "attachments" => [], "reactions" => [])

    get "/api/rooms/#{room.id}/messages", params: {external_id: observer.external_id, name: observer.name}
    visible = response.parsed_body.fetch("messages").find { |item| item.fetch("id") == message.id }
    expect(visible).to include("body" => "Секретное сообщение")
    expect(visible).not_to have_key("blocked")
  end
end
