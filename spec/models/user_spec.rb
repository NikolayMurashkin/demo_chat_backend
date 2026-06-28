# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe ".upsert_from_external" do
    it "returns the existing user without changing their name" do
      user = create(:user, name: "Исходное имя")

      result = described_class.upsert_from_external(external_id: user.external_id, name: "Другое имя")

      expect(result).to eq(user)
      expect(user.reload.name).to eq("Исходное имя")
    end

    it "creates one user for repeated requests with the same external id" do
      external_id = "same-user"

      first = described_class.upsert_from_external(external_id: external_id, name: "Первый запрос")
      second = described_class.upsert_from_external(external_id: external_id, name: "Второй запрос")

      expect(first).to eq(second)
      expect(described_class.where(external_id: external_id)).to contain_exactly(first)
    end
  end
end
