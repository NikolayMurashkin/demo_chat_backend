# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverScheduledMessageJob do
  it "publishes a due message once and marks the schedule as delivered" do
    author = create(:user)
    room = create(:room)
    room.add_member(author)
    scheduled = ScheduledMessage.create!(room: room, user: author, body: "Не забыть", deliver_at: 1.minute.ago)

    expect { described_class.perform_now(scheduled.id) }.to change(room.messages, :count).by(1)

    expect(room.messages.last).to have_attributes(body: "Не забыть", user: author)
    expect(scheduled.reload.delivered_at).to be_present
  end

  it "cancels a message whose author left the room before the delivery time" do
    author = create(:user)
    room = create(:room)
    room.add_member(author)
    room.add_member(create(:user))
    scheduled = ScheduledMessage.create!(room: room, user: author, body: "Уже не участник", deliver_at: 1.minute.ago)
    room.membership_for(author).destroy

    expect { described_class.perform_now(scheduled.id) }.not_to change(room.messages, :count)

    expect(scheduled.reload).to have_attributes(delivered_at: nil, cancelled_at: be_present)
  end
end
