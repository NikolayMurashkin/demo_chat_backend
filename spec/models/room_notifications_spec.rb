# frozen_string_literal: true

require "rails_helper"

RSpec.describe Room do
  def group_with(*users)
    Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
  end

  def incoming_to(member)
    frames = []
    allow(UserChannel).to receive(:broadcast_to) do |target, payload|
      frames << payload if target == member && payload[:type] == "incoming"
    end
    yield
    frames
  end

  it "asks for a notification in an ordinary chat" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)

    frames = incoming_to(member) do
      room.notify_incoming(room.messages.create!(user: author, body: "<p>привет</p>"))
    end

    expect(frames.first).to include(notify: true, mentioned: false)
  end

  it "keeps delivering the frame of a muted chat but asks not to notify" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)
    room.membership_for(member).update!(muted_at: Time.current)

    frames = incoming_to(member) do
      room.notify_incoming(room.messages.create!(user: author, body: "<p>привет</p>"))
    end

    # Кадр обязан дойти: по нему клиент подтягивает пропущенное сообщение. Молчит только звук.
    expect(frames.size).to eq(1)
    expect(frames.first).to include(notify: false, mentioned: false)
  end

  it "lets a mention pierce a muted chat" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)
    room.membership_for(member).update!(muted_at: Time.current)
    body = %(<p><span data-mention="#{member.external_id}">@#{member.name}</span></p>)

    frames = incoming_to(member) do
      room.notify_incoming(room.messages.create!(user: author, body: body))
    end

    expect(frames.first).to include(notify: true, mentioned: true)
  end

  it "delivers a silent message without asking for a notification" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)

    frames = incoming_to(member) do
      room.notify_incoming(room.messages.create!(user: author, body: "<p>привет</p>", silent: true))
    end

    expect(frames.size).to eq(1)
    expect(frames.first).to include(notify: false)
  end

  it "does not let a mention pierce a silent message" do
    author = create(:user)
    member = create(:user)
    room = group_with(author, member)
    body = %(<p><span data-mention="#{member.external_id}">@#{member.name}</span></p>)

    frames = incoming_to(member) do
      room.notify_incoming(room.messages.create!(user: author, body: body, silent: true))
    end

    # Тишину выбрал отправитель, и упоминание её не отменяет: иначе «без звука» ничего не значило бы.
    expect(frames.first).to include(notify: false, mentioned: true)
  end

  it "does not notify the author about their own message" do
    author = create(:user)
    room = group_with(author, create(:user))

    frames = incoming_to(author) do
      room.notify_incoming(room.messages.create!(user: author, body: "<p>привет</p>"))
    end

    expect(frames).to be_empty
  end
end
