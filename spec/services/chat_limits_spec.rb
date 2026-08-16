# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatLimits do
  describe ".rate" do
    it "returns the built-in threshold when the environment says nothing" do
      expect(described_class.rate(:message)).to eq({limit: 120, period: 60})
    end

    # Порог должен подбираться на живом стенде перезапуском, а не выкаткой: во время показа
    # правка кода — это минимум сборка образа и деплой.
    it "takes the threshold from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CHAT_LIMIT_MESSAGE").and_return("500")

      expect(described_class.rate(:message)).to eq({limit: 500, period: 60})
    end

    # Опечатка в переменной не должна ни ронять приложение, ни молча снимать ограничение.
    it "falls back to the built-in threshold when the environment holds junk" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CHAT_LIMIT_MESSAGE").and_return("много")

      expect(described_class.rate(:message)).to eq({limit: 120, period: 60})
    end
  end

  describe ".count" do
    it "takes the socket ceiling from the environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CHAT_MAX_SOCKETS_PER_USER").and_return("64")

      expect(described_class.count(:sockets_per_user)).to eq(64)
    end
  end
end
