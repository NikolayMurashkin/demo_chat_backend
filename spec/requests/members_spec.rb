# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Group members" do
  def group_with(owner, member)
    Room.create!(name: "Команда", owner: owner).tap do |room|
      room.add_member(owner)
      room.add_member(member)
    end
  end

  it "lets the owner remove a member without replacing the caller identity with the path parameter" do
    owner = create(:user)
    member = create(:user)
    room = group_with(owner, member)

    delete "/api/rooms/#{room.id}/members/#{member.external_id}", params: {
      external_id: owner.external_id, name: owner.name
    }

    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch("members")).not_to include(a_hash_including("external_id" => member.external_id))
    expect(room.reload.users).not_to include(member)
  end
end
