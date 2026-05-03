# frozen_string_literal: true

class RoomMembership < ApplicationRecord
  # Оформление чата: личное, поэтому живёт на связи, а не на комнате. Значение из списка,
  # а не произвольная строка — иначе им можно было бы подсунуть в класс что угодно.
  THEMES = %w[classic graphite forest sunset midnight].freeze
  DEFAULT_THEME = "classic"

  belongs_to :room
  belongs_to :user

  validates :user_id, uniqueness: {scope: :room_id}
  validates :theme, inclusion: {in: THEMES}, allow_nil: true

  # Приглушённый чат не молчит совсем: он остаётся в списке и считает непрочитанные,
  # но не даёт повода для звука и системного уведомления. Упоминание его пробивает.
  def muted?
    muted_at.present?
  end

  def pinned?
    pinned_at.present?
  end

  # Помечен непрочитанным вручную: точка в списке горит, пока чат не откроют.
  def marked_unread?
    marked_unread_at.present?
  end

  # Архивный чат уходит из основного списка в отдельную секцию, но продолжает считать
  # непрочитанные: архив — это «убрать с глаз», а не «отписаться».
  def archived?
    archived_at.present?
  end

  def theme_name
    theme.presence || DEFAULT_THEME
  end
end
