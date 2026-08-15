# frozen_string_literal: true

class PollVote < ApplicationRecord
  belongs_to :poll
  belongs_to :poll_option
  belongs_to :user

  validates :user_id, uniqueness: {scope: :poll_option_id}
end
