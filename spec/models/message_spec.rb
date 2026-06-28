# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message do
  describe ".normalized_body" do
    it "rejects markup without visible content" do
      expect(described_class.normalized_body('<p>&nbsp;</p><script></script>')).to be_nil
    end
  end

  it "strips active HTML before persisting a message" do
    message = create(:message, body: '<p>Hello <script>alert("xss")</script><strong>chat</strong></p>')

    expect(message.body).to eq("<p>Hello alert(\"xss\")<strong>chat</strong></p>")
    expect(message.plain_body).to eq('Hello alert("xss")chat')
  end
end
