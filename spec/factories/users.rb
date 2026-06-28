# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:external_id) { |number| "chat-user-#{number}" }
    sequence(:name) { |number| "Chat User #{number}" }
  end
end
