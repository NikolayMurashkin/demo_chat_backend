# Идемпотентно: чистим и пересоздаём демо-данные.
[Message, RoomMembership, Room, User].each(&:destroy_all)

me    = User.create!(name: "Николай")
julia = User.create!(name: "Юля Мазанова")
oleg  = User.create!(name: "Олег Петров")

general = Room.create!(name: "Общий чат")
dm      = Room.create!(name: "Юля Мазанова")

general.users << [me, julia, oleg]
dm.users << [me, julia]

general.messages.create!(user: julia, body: "Всем привет!")
general.messages.create!(user: oleg, body: "Здорово, коллеги")
dm.messages.create!(user: julia, body: "Николай, глянь макет, пожалуйста")
dm.messages.create!(user: me, body: "Ага, сейчас посмотрю")

puts "Готово: #{User.count} юзеров, #{Room.count} комнат, #{Message.count} сообщений"
