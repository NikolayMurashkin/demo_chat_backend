# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    sequence(:name) { |number| "Chat room #{number}" }
  end
end
