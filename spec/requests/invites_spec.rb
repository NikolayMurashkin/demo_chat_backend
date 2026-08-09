# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group invite links" do
  def identity(user)
    {external_id: user.external_id, name: user.name}
  end

  def group_with(owner)
    Room.create!(name: "Команда", owner: owner).tap { |room| room.add_member(owner) }
  end

  def issue_invite(owner, room)
    post "/api/rooms/#{room.id}/invite", params: identity(owner)
    response.parsed_body.fetch("token")
  end

  it "returns the same link on a repeated request" do
    owner = create(:user)
    room = group_with(owner)

    first = issue_invite(owner, room)
    second = issue_invite(owner, room)

    expect(first).to eq(second)
  end

  it "lets a newcomer join the group by the link" do
    owner = create(:user)
    room = group_with(owner)
    token = issue_invite(owner, room)
    newcomer = create(:user)

    post "/api/invites/#{token}/join", params: identity(newcomer)

    expect(response).to have_http_status(:created), response.body
    expect(room.reload.users).to include(newcomer)
  end

  it "shows what the group is before joining it" do
    owner = create(:user)
    room = group_with(owner)
    token = issue_invite(owner, room)

    get "/api/invites/#{token}", params: identity(create(:user))

    expect(response.parsed_body).to include("name" => "Команда", "members_count" => 1, "joined" => false)
  end

  it "stops working after the owner revokes it" do
    owner = create(:user)
    room = group_with(owner)
    token = issue_invite(owner, room)

    delete "/api/rooms/#{room.id}/invite", params: identity(owner)
    post "/api/invites/#{token}/join", params: identity(create(:user))

    expect(response).to have_http_status(:not_found)
    expect(room.reload.users.count).to eq(1)
  end

  it "does not let an ordinary member issue the link" do
    owner = create(:user)
    member = create(:user)
    room = group_with(owner).tap { |group| group.add_member(member) }

    post "/api/rooms/#{room.id}/invite", params: identity(member)

    expect(response).to have_http_status(:forbidden)
    expect(room.reload.invite_token).to be_nil
  end
end
