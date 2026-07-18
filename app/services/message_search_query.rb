# frozen_string_literal: true

# Разбор строки поиска на текст и фильтры: `from:иван has:file отчёт`.
#
# Живёт отдельно от контроллеров, потому что синтаксис один на оба поиска — глобальный
# (панель диалогов) и внутри диалога. Неизвестный фильтр остаётся обычным словом запроса:
# человек мог искать текст с двоеточием, и молча терять его нельзя.
class MessageSearchQuery
  # Фильтр отделяем от текста только у известных ключей и непустого значения.
  FILTER_PATTERN = /\A(from|has):(\S+)\z/i
  ALLOWED_HAS = %w[link file].freeze
  # Кто спрашивает: `from:me` избавляет от необходимости писать собственное имя.
  SELF_ALIASES = %w[me я].freeze

  attr_reader :text, :from, :has

  def initialize(raw)
    @from = nil
    @has = []
    @text = raw.to_s.strip.split(/\s+/).reject { |word| consume_filter(word) }.join(" ")
  end

  # Пустым считается запрос без текста И без фильтров: `has:file` сам по себе — валидный поиск.
  def blank?
    text.blank? && from.blank? && has.empty?
  end

  def from_self?
    SELF_ALIASES.include?(from.to_s.downcase)
  end

  def apply(scope, viewer:)
    scope = scope.matching(text) if text.present?
    scope = apply_author(scope, viewer)
    scope = scope.with_link if has.include?("link")
    scope = scope.with_attachment if has.include?("file")
    scope
  end

  private

  def apply_author(scope, viewer)
    return scope if from.blank?
    return scope.where(user_id: viewer.id) if from_self?

    scope.where(user_id: matching_author_ids(viewer))
  end

  # Совпадение по имени считаем в руби, а не через LOWER() в SQL: SQLite приводит регистр
  # только у ASCII, поэтому на dev-базе «from:петров» не нашёл бы «Петрова». Круг кандидатов
  # ограничен собеседниками и самим спрашивающим — искать всё равно можно только в своих комнатах.
  def matching_author_ids(viewer)
    needle = from.downcase

    User.sharing_rooms_with(viewer).or(User.where(id: viewer.id))
        .pluck(:id, :name)
        .filter_map { |id, name| id if name.to_s.downcase.include?(needle) }
  end

  # Возвращает true, если слово было фильтром и в текст запроса попасть не должно.
  def consume_filter(word)
    match = FILTER_PATTERN.match(word)
    return false unless match

    key = match[1].downcase
    value = match[2]

    return consume_has(value) if key == "has"

    @from = value
    true
  end

  def consume_has(value)
    return false unless ALLOWED_HAS.include?(value.downcase)

    @has << value.downcase
    true
  end
end
