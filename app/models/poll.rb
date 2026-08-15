# frozen_string_literal: true

# Опрос при сообщении. Голоса не анонимны для подсчёта, но наружу отдаются только числами:
# кто как проголосовал, в демо не показываем — это лишний повод к неловкости в рабочем чате.
class Poll < ApplicationRecord
  MAX_QUESTION_LENGTH = 300
  MAX_OPTION_LENGTH = 120
  MAX_OPTIONS = 10
  MIN_OPTIONS = 2

  belongs_to :message
  has_many :poll_options, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :poll
  has_many :poll_votes, dependent: :destroy

  validates :question, presence: true, length: {maximum: MAX_QUESTION_LENGTH}

  def closed?
    closed_at.present?
  end

  # Закрывать опрос может только тот, кто его создал.
  def owned_by?(user)
    message.user_id == user.id
  end

  # Сколько человек участвовало: в опросе с несколькими ответами голосов больше, чем людей,
  # и проценты по числу голосов давали бы в сумме больше ста.
  def voters_count
    poll_votes.map(&:user_id).uniq.size
  end

  # Свой голос участник отдаёт один раз — второй запрос опрос уже не принимает.
  def voted_by?(user)
    poll_votes.exists?(user: user)
  end

  def as_chat_json(viewer: nil)
    votes = poll_votes.to_a
    my_option_ids = viewer ? votes.select { |vote| vote.user_id == viewer.id }.map(&:poll_option_id) : []

    {
      id: id,
      question: question,
      multiple: multiple,
      closed: closed?,
      voters_count: votes.map(&:user_id).uniq.size,
      # Проголосовавший видит результаты, остальные — только варианты: иначе первый же
      # открывший чат узнаёт распределение и голосует «как все».
      voted: my_option_ids.any?,
      options: poll_options.map do |option|
        {
          id: option.id,
          text: option.text,
          votes_count: votes.count { |vote| vote.poll_option_id == option.id },
          chosen: my_option_ids.include?(option.id)
        }
      end
    }
  end
end
