# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationCable::Connection do
  def connect_user(external_id, name: "Диагностика")
    connect("/cable?external_id=#{external_id}&name=#{CGI.escape(name)}", headers: {"Origin" => "http://localhost:3000"})
  end

  it "identifies the user by the external id from the cable url" do
    connect_user("presence-user")

    expect(connection.current_user.external_id).to eq("presence-user")
  end

  it "rejects a connection from an origin outside CORS_ORIGINS" do
    expect do
      connect("/cable?external_id=presence-user&name=X", headers: {"Origin" => "https://evil.example"})
    end.to have_rejected_connection
  end

  # Тесный лимит сокетов запирал человека наглухо: сервер замечает оборванные соединения
  # не сразу, накопленные «фантомы» съедали квоту, и подключиться заново уже не выходило —
  # чат показывал вечное «соединение восстанавливается». Лишние вкладки теперь вытесняются,
  # а новое подключение проходит всегда.
  it "keeps accepting new sockets of the same user" do
    # Отказ поднял бы UnauthorizedError и уронил пример прямо здесь.
    12.times { connect_user("busy-user") }

    expect(connection.current_user.external_id).to eq("busy-user")
  end
end
