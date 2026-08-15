# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Polls" do
  def identity(user)
    {external_id: user.external_id, name: user.name}
  end

  def group_with(*users)
    Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
  end

  def create_poll(user, room, params = {})
    post "/api/rooms/#{room.id}/polls",
      params: identity(user).merge({question: "Когда встречаемся?", options: %w[Сегодня Завтра]}.merge(params))
    response.parsed_body
  end

  it "delivers the poll as an ordinary message of the room timeline" do
    author = create(:user)
    room = group_with(author, create(:user))

    body = create_poll(author, room)

    expect(response).to have_http_status(:created), response.body
    expect(body.dig("poll", "question")).to eq("Когда встречаемся?")
    expect(body.dig("poll", "options").map { |option| option.fetch("text") }).to eq(%w[Сегодня Завтра])
    expect(room.messages.count).to eq(1)
  end

  it "refuses a poll with a single option" do
    author = create(:user)
    room = group_with(author, create(:user))

    create_poll(author, room, options: ["Только один"])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch("error")).to eq("options_required")
  end

  it "keeps the first vote when the voter tries to change it" do
    author = create(:user)
    voter = create(:user)
    room = group_with(author, voter)
    poll_id = create_poll(author, room).fetch("poll").fetch("id")
    poll = Poll.find(poll_id)
    first, second = poll.poll_options.to_a

    post "/api/polls/#{poll_id}/votes", params: identity(voter).merge(option_ids: [first.id])
    post "/api/polls/#{poll_id}/votes", params: identity(voter).merge(option_ids: [second.id])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch("error")).to eq("already_voted")
    expect(poll.poll_votes.where(user: voter).pluck(:poll_option_id)).to eq([first.id])
  end

  it "keeps both answers in a multiple-choice poll" do
    author = create(:user)
    voter = create(:user)
    room = group_with(author, voter)
    poll_id = create_poll(author, room, multiple: true).fetch("poll").fetch("id")
    poll = Poll.find(poll_id)

    post "/api/polls/#{poll_id}/votes", params: identity(voter).merge(option_ids: poll.poll_options.pluck(:id))

    expect(response).to have_http_status(:ok), response.body
    expect(poll.poll_votes.where(user: voter).count).to eq(2)
    expect(response.parsed_body.fetch("voters_count")).to eq(1)
  end

  it "refuses a vote from someone outside the room" do
    author = create(:user)
    room = group_with(author, create(:user))
    poll_id = create_poll(author, room).fetch("poll").fetch("id")
    option_id = Poll.find(poll_id).poll_options.first.id

    post "/api/polls/#{poll_id}/votes", params: identity(create(:user)).merge(option_ids: [option_id])

    expect(response).to have_http_status(:not_found)
    expect(PollVote.count).to be_zero
  end

  it "stops accepting votes once the author closes the poll" do
    author = create(:user)
    voter = create(:user)
    room = group_with(author, voter)
    poll_id = create_poll(author, room).fetch("poll").fetch("id")
    option_id = Poll.find(poll_id).poll_options.first.id

    post "/api/polls/#{poll_id}/close", params: identity(author)
    post "/api/polls/#{poll_id}/votes", params: identity(voter).merge(option_ids: [option_id])

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.fetch("error")).to eq("poll_closed")
  end

  it "lets only the author close the poll" do
    author = create(:user)
    voter = create(:user)
    room = group_with(author, voter)
    poll_id = create_poll(author, room).fetch("poll").fetch("id")

    post "/api/polls/#{poll_id}/close", params: identity(voter)

    expect(response).to have_http_status(:forbidden)
    expect(Poll.find(poll_id)).not_to be_closed
  end
end
