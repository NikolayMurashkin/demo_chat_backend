Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    get "status", to: "statuses#show"
    patch "status", to: "statuses#update"
    # Глобальный поиск панели диалогов: чаты по названию + сообщения по всем комнатам.
    get "search", to: "search#index"
    # Пересылка кросс-комнатная, поэтому вне вложенного ресурса комнаты.
    post "messages/forward", to: "messages#forward"
    post "messages/:id/save", to: "messages#save"
    # Личная отметка «важное» и раскрытие одноразового сообщения адресуются самому сообщению:
    # обе ручки работают с сообщением из любой доступной пользователю комнаты.
    post "messages/:id/star", to: "messages#star"
    delete "messages/:id/star", to: "messages#unstar"
    post "messages/:id/view", to: "messages#view"
    get "starred_messages", to: "starred_messages#index"
    post "rooms/saved", to: "rooms#saved"

    # Папки чатов — личные вкладки над списком диалогов.
    resources :chat_folders, only: %i[index create update destroy]

    # Приглашение по ссылке: токен вместо id комнаты, поэтому маршрут отдельный от rooms.
    get "invites/:token", to: "invites#show", constraints: {token: %r{[^/]+}}
    post "invites/:token/join", to: "invites#join", constraints: {token: %r{[^/]+}}

    # Голос и закрытие адресуются опросу, а не комнате: голосующий приходит из любого чата,
    # где ему это сообщение видно.
    post "polls/:id/votes", to: "polls#vote"
    post "polls/:id/close", to: "polls#close"

    resources :rooms, only: %i[index show create update destroy] do
      collection do
        post :group, to: "rooms#create_group"
      end

      member do
        post :block, to: "blocks#create"
        delete :block, to: "blocks#destroy"
        # Срок жизни исчезающих сообщений задаёт любой участник, а не только создатель группы:
        # это настройка переписки, а не её оформления.
        patch :ttl, to: "rooms#update_ttl"
        post :invite, to: "invites#create"
        delete :invite, to: "invites#destroy"
        post :channels, to: "channels#create"
      end

      # Приглушение, закрепление и ручная пометка «непрочитано» — настройки участника, не комнаты.
      patch "membership", to: "memberships#update"
      # «Прочитать» чат целиком, не открывая его: открытый двигает отметку сам по WS, а из
      # списка чатов нужен тот же переход снаружи — накопившееся не дочитывают, а закрывают.
      post "membership/read", to: "memberships#read"

      # Опрос создаётся в комнате: он приезжает обычным сообщением её ленты.
      resources :polls, only: %i[create]

      resources :messages, only: %i[index create] do
        collection do
          get :search
        end

        member do
          get :thread
          # Кто уже прочитал сообщение — список имён под галочками «прочитано».
          get :readers
        end
      end

      resources :scheduled_messages, only: %i[index create update destroy]

      # Вкладка «Медиа»: вложения и ссылки комнаты одним списком.
      get "attachments", to: "attachments#index"

      # Приглашение в группу. Выход из неё — тот же DELETE /api/rooms/:id, что и удаление чата,
      # а исключает участника создатель по внешнему id (uuid профиля платформы).
      post "members", to: "members#create"
      delete "members/:member_external_id", to: "members#destroy", constraints: {member_external_id: %r{[^/]+}}
    end
  end
end
