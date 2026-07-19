Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    # Глобальный поиск панели диалогов: чаты по названию + сообщения по всем комнатам.
    get "search", to: "search#index"
    # Пересылка кросс-комнатная, поэтому вне вложенного ресурса комнаты.
    post "messages/forward", to: "messages#forward"

    resources :rooms, only: %i[index show create update destroy] do
      collection do
        post :group, to: "rooms#create_group"
      end

      resources :messages, only: %i[index create] do
        collection do
          get :search
        end

        member do
          get :thread
        end
      end

      # Вкладка «Медиа»: вложения и ссылки комнаты одним списком.
      get "attachments", to: "attachments#index"

      # Приглашение в группу. Выход из неё — тот же DELETE /api/rooms/:id, что и удаление чата,
      # а исключает участника создатель по внешнему id (uuid профиля платформы).
      post "members", to: "members#create"
      delete "members/:member_external_id", to: "members#destroy", constraints: {member_external_id: %r{[^/]+}}
    end
  end
end
