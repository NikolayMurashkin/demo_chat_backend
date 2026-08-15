# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatChannel do
  def group_with(owner, member)
    Room.create!(name: "Команда", owner: owner).tap do |room|
      room.add_member(owner)
      room.add_member(member)
    end
  end

  def connect_as(user)
    stub_connection(current_user: user)
  end

  it "rejects a subscription to a room the user does not belong to" do
    outsider = create(:user)
    room = group_with(create(:user), create(:user))

    connect_as(outsider)
    subscribe(room_id: room.id)

    expect(subscription).to be_rejected
  end

  describe "membership revoked while the socket stays open" do
    it "stops accepting messages from a member removed from the group" do
      owner = create(:user)
      member = create(:user)
      room = group_with(owner, member)

      connect_as(member)
      subscribe(room_id: room.id)
      expect(subscription).to be_confirmed

      room.membership_for(member).destroy

      expect { perform(:send_message, "body" => "всё ещё тут") }.not_to change(Message, :count)
    end

    it "stops accepting messages after the room is deleted for everyone" do
      owner = create(:user)
      member = create(:user)
      room = group_with(owner, member)

      connect_as(member)
      subscribe(room_id: room.id)
      room.destroy!

      expect { perform(:send_message, "body" => "в пустоту") }.not_to change(Message, :count)
    end

    it "stops accepting reactions from a removed member" do
      owner = create(:user)
      member = create(:user)
      room = group_with(owner, member)
      message = create(:message, room: room, user: owner)

      connect_as(member)
      subscribe(room_id: room.id)
      room.membership_for(member).destroy

      expect { perform(:toggle_reaction, "message_id" => message.id, "emoji" => "👍") }
        .not_to change(MessageReaction, :count)
    end
  end

  describe "rejection feedback" do
    it "tells the author why the message was not saved instead of dropping it silently" do
      author = create(:user)
      peer = create(:user)
      room = Room.create!(dm_key: "dm:test").tap do |created|
        created.add_member(author)
        created.add_member(peer)
      end
      UserBlock.create!(blocker: peer, blocked: author)
      client_message_id = "8f14e45f-ceea-4a67-a5e8-9b1c2d3e4f50"

      connect_as(author)
      subscribe(room_id: room.id)

      expect { perform(:send_message, "body" => "привет", "client_message_id" => client_message_id) }
        .to have_broadcasted_to([room, author])
        .with(hash_including(type: "message_rejected", reason: "blocked", client_message_id: client_message_id))
    end

    it "reports an over-long body rather than leaving the bubble pending" do
      author = create(:user)
      room = group_with(author, create(:user))

      connect_as(author)
      subscribe(room_id: room.id)

      expect { perform(:send_message, "body" => "a" * (described_class::MAX_BODY_LENGTH + 1)) }
        .to have_broadcasted_to([room, author]).with(hash_including(type: "message_rejected", reason: "too_long"))
    end
  end

  describe "mark_read" do
    it "clears a chat the user had marked unread by hand" do
      reader = create(:user)
      room = group_with(create(:user), reader)
      room.membership_for(reader).update!(marked_unread_at: Time.current)

      connect_as(reader)
      subscribe(room_id: room.id)
      perform(:mark_read)

      expect(room.membership_for(reader)).not_to be_marked_unread
    end
  end

  describe "typing" do
    # ActionCable отдаёт data только методу с arity == 1. Пока у typing было значение по
    # умолчанию, метод вызывался без аргумента: kind терялся, а «перестал печатать» не уходил.
    it "passes the payload through instead of falling back to an empty hash" do
      author = create(:user)
      member = create(:user)
      room = group_with(author, member)

      connect_as(author)
      subscribe(room_id: room.id)

      expect { perform(:typing, "kind" => "voice", "active" => false) }
        .to have_broadcasted_to([room, member])
        .with(hash_including(type: "typing", kind: "voice", active: false))
    end

    it "reports an ongoing activity as active" do
      author = create(:user)
      member = create(:user)
      room = group_with(author, member)

      connect_as(author)
      subscribe(room_id: room.id)

      expect { perform(:typing, "kind" => "typing", "active" => true) }
        .to have_broadcasted_to([room, member])
        .with(hash_including(type: "typing", kind: "typing", active: true))
    end

    it "does not reach a group member who blocked the author" do
      author = create(:user)
      blocker = create(:user)
      room = group_with(author, blocker)
      UserBlock.create!(blocker: blocker, blocked: author)

      connect_as(author)
      subscribe(room_id: room.id)

      expect { perform(:typing, "kind" => "typing") }.not_to have_broadcasted_to([room, blocker])
    end
  end
end
