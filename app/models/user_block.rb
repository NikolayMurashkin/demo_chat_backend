# frozen_string_literal: true

class UserBlock < ApplicationRecord
  belongs_to :blocker, class_name: "User"
  belongs_to :blocked, class_name: "User"

  validates :blocked_id, uniqueness: {scope: :blocker_id}
  validate :blocker_and_blocked_are_different

  private

  def blocker_and_blocked_are_different
    errors.add(:blocked, "must be different from blocker") if blocker_id == blocked_id
  end
end
