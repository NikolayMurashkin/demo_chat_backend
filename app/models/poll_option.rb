# frozen_string_literal: true

class PollOption < ApplicationRecord
  belongs_to :poll
  has_many :poll_votes, dependent: :destroy

  validates :text, presence: true, length: {maximum: Poll::MAX_OPTION_LENGTH}
end
