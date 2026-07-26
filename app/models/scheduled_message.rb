# frozen_string_literal: true

class ScheduledMessage < ApplicationRecord
  belongs_to :room
  belongs_to :user

  scope :pending, -> { where(cancelled_at: nil, delivered_at: nil) }
end
