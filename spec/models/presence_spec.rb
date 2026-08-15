# frozen_string_literal: true

require "rails_helper"

RSpec.describe Presence do
  after { described_class::SOCKETS.clear }

  describe ".connect" do
    it "reports the first socket of a user separately from the following ones" do
      user_id = 1

      expect(described_class.connect(user_id)).to be(:first)
      expect(described_class.connect(user_id)).to be(:connected)
    end

    # Раньше счётчик отказывал по достижении лимита, и человек оставался офлайн до перезапуска
    # процесса: оборванные сокеты (уснувший ноутбук, пропавшая сеть) сервер замечает не сразу,
    # и накопленные «фантомы» не давали подключиться заново. Лишние вкладки теперь закрывает
    # Connection, а счётчик именно считает.
    it "keeps accepting sockets instead of locking the user out" do
      user_id = 2

      20.times { described_class.connect(user_id) }

      expect(described_class.connect(user_id)).to be(:connected)
      expect(described_class).to be_online(user_id)
    end
  end

  describe ".disconnect" do
    it "reports offline only when the last socket is gone" do
      user_id = 3
      2.times { described_class.connect(user_id) }

      expect(described_class.disconnect(user_id)).to be(false)
      expect(described_class.disconnect(user_id)).to be(true)
      expect(described_class).not_to be_online(user_id)
    end
  end
end
