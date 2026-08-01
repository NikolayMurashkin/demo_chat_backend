# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chat status" do
  describe "PATCH /api/status" do
    it "saves one of the three statuses and a safe custom label" do
      user = create(:user)

      patch "/api/status", params: {
        external_id: user.external_id,
        name: user.name,
        status: "dnd",
        status_text: "На встрече"
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body).to eq({"status" => "dnd", "status_text" => "На встрече"})
      expect(user.reload).to have_attributes(chat_status: "dnd", chat_status_text: "На встрече")
    end

    it "uses the default label when the optional text is empty" do
      user = create(:user)

      patch "/api/status", params: {
        external_id: user.external_id, name: user.name, status: "away", status_text: ""
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body).to eq({"status" => "away", "status_text" => "Отошел"})
    end

    it "rejects a status text consisting only of whitespace" do
      user = create(:user)

      patch "/api/status", params: {
        external_id: user.external_id, name: user.name, status: "away", status_text: "   "
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({"error" => "invalid_status_text"})
    end

    it "rejects an unknown status and leaves the stored status unchanged" do
      user = create(:user)

      expect {
        patch "/api/status", params: {
          external_id: user.external_id, name: user.name, status: "invisible", status_text: "Скрыт"
        }
      }.not_to change { user.reload.chat_status }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({"error" => "invalid_status"})
    end

    it "rejects markup-sized text over 50 graphemes and removes invisible control characters" do
      user = create(:user)

      patch "/api/status", params: {
        external_id: user.external_id, name: user.name, status: "away", status_text: "a" * 51
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({"error" => "invalid_status_text"})

      patch "/api/status", params: {
        external_id: user.external_id, name: user.name, status: "away", status_text: "<b>Отошел</b>\u202E"
      }

      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch("status_text")).to eq("bОтошел/b")
    end
  end
end
