# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatRateLimiter do
  describe ".allow?" do
    it "rejects calls over the configured limit" do
      key = "spec:#{SecureRandom.uuid}"

      expect(described_class.allow?(key, limit: 2, period: 60)).to be(true)
      expect(described_class.allow?(key, limit: 2, period: 60)).to be(true)
      expect(described_class.allow?(key, limit: 2, period: 60)).to be(false)
    end
  end
end
