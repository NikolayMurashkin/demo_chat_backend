# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserChannel do
  def direct_room(user_a, user_b)
    Room.create!(dm_key: "dm:#{[user_a.id, user_b.id].sort.join('-')}").tap do |room|
      room.add_member(user_a)
      room.add_member(user_b)
    end
  end

  def call_signal_payload(type, call_id:, room:, peer:, payload: nil)
    {
      "type" => type,
      "call_id" => call_id,
      "room_id" => room.id,
      "to_external_id" => peer.external_id,
      "payload" => payload
    }
  end

  def ice_candidate(index)
    {"candidate" => "candidate:#{index} 1 udp 2113937151 192.168.0.#{index % 250} 5#{index} typ host", "sdpMid" => "0"}
  end

  # Подписка повторяется на каждый реконнект и на каждую перезагрузку страницы, а прежний
  # потолок в десять штук в минуту выедался за минуту работы. Отказ терминален: клиент
  # отклонённую подписку не повторяет, и человек оставался с живым сокетом, но без входящих
  # звонков и без обновления списка чатов — до перезагрузки вкладки.
  it "keeps confirming the personal subscription however often the socket reconnects" do
    user = create(:user)
    stub_connection(current_user: user)

    30.times do
      subscribe
      expect(subscription).to be_confirmed
    end
  end

  describe "call signalling" do
    let(:caller_user) { create(:user) }
    let(:peer) { create(:user) }
    let(:room) { direct_room(caller_user, peer) }
    let(:call_id) { SecureRandom.uuid }

    before do
      stub_connection(current_user: caller_user)
      subscribe
    end

    # Кандидатов столько, сколько у машины сетевых интерфейсов: ноутбук с VPN и виртуальными
    # адаптерами выдаёт их десятками. Минутный бюджет в 90 штук выедала вторая попытка дозвона,
    # причём отбрасывались ПОСЛЕДНИЕ кандидаты — то есть srflx, единственные, которыми
    # соединяются разные сети.
    it "relays a full ICE exchange of a single call without dropping candidates" do
      expect do
        200.times { |index| perform(:call_signal, call_signal_payload("call_ice", call_id: call_id, room: room, peer: peer, payload: {"candidate" => ice_candidate(index)})) }
      end.to have_broadcasted_to(peer).from_channel(described_class).exactly(200).times
    end

    # Бюджет ICE считается на звонок, поэтому повторный дозвон начинает со своим бюджетом,
    # а не доедает остаток предыдущего.
    it "gives a redialled call its own ICE budget" do
      redial_id = SecureRandom.uuid
      120.times { |index| perform(:call_signal, call_signal_payload("call_ice", call_id: call_id, room: room, peer: peer, payload: {"candidate" => ice_candidate(index)})) }

      expect do
        120.times { |index| perform(:call_signal, call_signal_payload("call_ice", call_id: redial_id, room: room, peer: peer, payload: {"candidate" => ice_candidate(index)})) }
      end.to have_broadcasted_to(peer).from_channel(described_class).exactly(120).times
    end

    # Молчание в ответ на отброшенный сигнал неотличимо от неисправной сети: звонящий видит
    # гудки, вызываемый — тишину. Причину возвращаем отправителю.
    it "tells the sender why a signal was not relayed" do
      stranger = create(:user)

      perform(:call_signal, call_signal_payload("call_invite", call_id: call_id, room: room, peer: stranger, payload: {"sdp" => {"type" => "offer", "sdp" => "v=0"}}))

      expect(transmissions.last).to include("type" => "call_signal_rejected", "reason" => "peer_unavailable")
    end

    it "reports an ICE budget that ran out instead of dropping the candidate silently" do
      allow(ChatLimits).to receive(:rate).and_call_original
      allow(ChatLimits).to receive(:rate).with(:call_ice).and_return({limit: 1, period: 300})

      2.times { |index| perform(:call_signal, call_signal_payload("call_ice", call_id: call_id, room: room, peer: peer, payload: {"candidate" => ice_candidate(index)})) }

      expect(transmissions.last).to include("type" => "call_signal_rejected", "reason" => "rate_limited")
    end
  end
end
