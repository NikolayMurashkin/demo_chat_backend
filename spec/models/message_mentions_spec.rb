# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message do
  def group_with(*users)
    Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
  end

  def mention(user, text: "@#{user.name}")
    %(<span data-mention="#{user.external_id}">#{text}</span>)
  end

  it "records a mention of a room member" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)

    message = room.messages.create!(user: author, body: "<p>Привет, #{mention(member)}</p>")

    expect(message.mentioned_user_ids).to eq([member.id])
    expect(message.mentions?(member)).to be(true)
  end

  it "ignores a mention of somebody outside the room" do
    author = create(:user)
    outsider = create(:user)
    room = group_with(author, create(:user))

    message = room.messages.create!(user: author, body: "<p>#{mention(outsider)}</p>")

    expect(message.mentioned_user_ids).to be_empty
  end

  it "does not mention the author themselves" do
    author = create(:user)
    room = group_with(author, create(:user))

    message = room.messages.create!(user: author, body: "<p>#{mention(author)}</p>")

    expect(message.mentioned_user_ids).to be_empty
  end

  it "rebuilds mentions when the body is edited" do
    author = create(:user)
    first = create(:user)
    second = create(:user)
    room = group_with(author, first, second)
    message = room.messages.create!(user: author, body: "<p>#{mention(first)}</p>")

    message.update!(body: "<p>#{mention(second)}</p>")

    expect(message.reload.mentioned_user_ids).to eq([second.id])
  end

  it "drops mentions when the message is soft deleted" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)
    message = room.messages.create!(user: author, body: "<p>#{mention(member)}</p>")

    message.soft_delete!

    expect(message.reload.mentioned_user_ids).to be_empty
  end

  it "survives sanitization of the mention markup" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)

    message = room.messages.create!(
      user: author,
      body: %(<p><span data-mention="#{member.external_id}" onclick="steal()">@кто-то</span></p>),
    )

    expect(message.body).not_to include("onclick")
    expect(message.mentioned_user_ids).to eq([member.id])
  end

  it "counts only unread mentions for the room badge" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)
    room.messages.create!(user: author, body: "<p>#{mention(member)}</p>")

    expect(room.mention_unread_count_for(member)).to eq(1)

    room.membership_for(member).update!(last_read_at: Time.current)

    expect(room.mention_unread_count_for(member)).to eq(0)
  end
end
