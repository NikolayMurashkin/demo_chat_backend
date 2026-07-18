# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageSearchQuery do
  it "splits filters out of the text" do
    query = described_class.new("from:иван has:file отчёт за июль")

    expect(query.from).to eq("иван")
    expect(query.has).to eq(["file"])
    expect(query.text).to eq("отчёт за июль")
  end

  it "keeps an unknown filter as ordinary search text" do
    query = described_class.new("has:banana ссылка:тут")

    expect(query.has).to be_empty
    expect(query.text).to eq("has:banana ссылка:тут")
  end

  it "treats a filter-only query as a real search" do
    expect(described_class.new("has:link")).not_to be_blank
    expect(described_class.new("   ")).to be_blank
  end

  describe "#apply" do
    def room_with(*users)
      Room.create!(name: "Команда").tap { |room| users.each { |user| room.add_member(user) } }
    end

    it "filters by author name" do
      author = create(:user, name: "Иван Петров")
      other = create(:user, name: "Пётр Иванов")
      room = room_with(author, other)
      mine = create(:message, room: room, user: author, body: "<p>отчёт</p>")
      create(:message, room: room, user: other, body: "<p>отчёт</p>")

      # «Иванов» есть в имени второго участника, поэтому фильтр обязан смотреть на автора,
      # а не на текст: иначе выдача не сузилась бы вовсе.
      found = described_class.new("from:Петров отчёт").apply(room.messages, viewer: other)

      expect(found.map(&:id)).to eq([mine.id])
    end

    it "resolves from:me to the viewer" do
      viewer = create(:user)
      other = create(:user)
      room = room_with(viewer, other)
      mine = create(:message, room: room, user: viewer)
      create(:message, room: room, user: other)

      found = described_class.new("from:me").apply(room.messages, viewer: viewer)

      expect(found.map(&:id)).to eq([mine.id])
    end

    it "finds messages with a link both typed as text and inserted as markup" do
      user = create(:user)
      room = room_with(user)
      typed = create(:message, room: room, user: user, body: "<p>смотри https://example.com/a</p>")
      marked_up = create(:message, room: room, user: user, body: %(<p><a href="https://example.com/b">тут</a></p>))
      create(:message, room: room, user: user, body: "<p>без ссылок</p>")

      found = described_class.new("has:link").apply(room.messages, viewer: user)

      expect(found.map(&:id)).to contain_exactly(typed.id, marked_up.id)
    end

    it "finds only messages with attachments" do
      user = create(:user)
      room = room_with(user)
      with_file = create(:message, room: room, user: user)
      with_file.message_attachments.create!(kind: "file", filename: "note.txt", content_type: "text/plain", byte_size: 4)
      create(:message, room: room, user: user)

      found = described_class.new("has:file").apply(room.messages, viewer: user)

      expect(found.map(&:id)).to eq([with_file.id])
    end
  end
end
