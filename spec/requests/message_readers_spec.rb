# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Message readers" do
  def identity(user)
    {external_id: user.external_id, name: user.name}
  end

  def group_with(*users)
    Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
  end

  it "lists the participants whose read mark is not older than the message" do
    author = create(:user)
    reader = create(:user)
    latecomer = create(:user)
    room = group_with(author, reader, latecomer)
    message = create(:message, room: room, user: author)
    room.membership_for(reader).update!(last_read_at: message.created_at + 1.second)
    room.membership_for(latecomer).update!(last_read_at: message.created_at - 1.second)

    get "/api/rooms/#{room.id}/messages/#{message.id}/readers", params: identity(author)

    expect(response.parsed_body.fetch("readers").map { |item| item.fetch("external_id") })
      .to eq([reader.external_id])
    expect(response.parsed_body.fetch("recipients_count")).to eq(2)
  end

  it "never counts the author among the readers of their own message" do
    author = create(:user)
    room = group_with(author, create(:user))
    message = create(:message, room: room, user: author)
    room.membership_for(author).update!(last_read_at: Time.current)

    get "/api/rooms/#{room.id}/messages/#{message.id}/readers", params: identity(author)

    expect(response.parsed_body.fetch("readers")).to be_empty
  end

  it "refuses the list to someone outside the room" do
    room = group_with(create(:user), create(:user))
    message = create(:message, room: room, user: room.users.first)

    get "/api/rooms/#{room.id}/messages/#{message.id}/readers", params: identity(create(:user))

    expect(response).to have_http_status(:not_found)
  end
end
