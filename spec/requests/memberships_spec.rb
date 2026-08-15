# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chat membership settings" do
  def identity(user)
    {external_id: user.external_id, name: user.name}
  end

  def group_with(*users)
    Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
  end

  def patch_membership(user, room, params)
    patch "/api/rooms/#{room.id}/membership", params: identity(user).merge(params)
  end

  def room_summaries(user)
    get "/api/rooms", params: identity(user)
    response.parsed_body
  end

  it "stores the three settings independently for each participant" do
    user = create(:user)
    peer = create(:user)
    room = group_with(user, peer)

    patch_membership(user, room, muted: true, pinned: true, marked_unread: true)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "room_id" => room.id, "muted" => true, "pinned" => true, "marked_unread" => true
    )
    expect(room.membership_for(peer)).not_to be_muted
  end

  it "leaves untouched settings alone" do
    user = create(:user)
    room = group_with(user, create(:user))
    patch_membership(user, room, muted: true, pinned: true)

    patch_membership(user, room, muted: false)

    expect(response.parsed_body).to include("muted" => false, "pinned" => true)
  end

  it "exposes the settings in the room list" do
    user = create(:user)
    room = group_with(user, create(:user))
    patch_membership(user, room, muted: true, marked_unread: true)

    summary = room_summaries(user).first

    expect(summary).to include("muted" => true, "pinned" => false, "marked_unread" => true)
  end

  it "keeps the chat theme personal and shows it in the room list" do
    user = create(:user)
    peer = create(:user)
    room = group_with(user, peer)

    patch_membership(user, room, theme: "graphite")

    expect(response.parsed_body).to include("theme" => "graphite")
    expect(room_summaries(user).first).to include("theme" => "graphite")
    expect(room_summaries(peer).first).to include("theme" => RoomMembership::DEFAULT_THEME)
  end

  it "rejects a theme outside the known set" do
    user = create(:user)
    room = group_with(user, create(:user))

    patch_membership(user, room, theme: "neon")

    expect(response).to have_http_status(:unprocessable_content)
    expect(room.membership_for(user).theme_name).to eq(RoomMembership::DEFAULT_THEME)
  end

  it "archives the chat and returns it back" do
    user = create(:user)
    room = group_with(user, create(:user))

    patch_membership(user, room, archived: true)
    expect(room_summaries(user).first).to include("archived" => true)

    patch_membership(user, room, archived: false)
    expect(room_summaries(user).first).to include("archived" => false)
  end

  it "puts pinned chats above fresher conversations" do
    user = create(:user)
    quiet = group_with(user, create(:user))
    busy = group_with(user, create(:user))
    create(:message, room: busy, user: user)
    patch_membership(user, quiet, pinned: true)

    expect(room_summaries(user).map { |room| room.fetch("id") }).to eq([quiet.id, busy.id])
  end

  it "refuses a room the user does not belong to" do
    outsider = create(:user)
    room = group_with(create(:user), create(:user))

    patch_membership(outsider, room, muted: true)

    expect(response).to have_http_status(:not_found)
  end
end
