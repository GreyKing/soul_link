Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Discord OAuth
  get    "/login",                  to: "sessions#new",     as: :login
  post   "/auth/discord/callback",  to: "sessions#create"
  get    "/auth/discord/callback",  to: "sessions#create"
  get    "/auth/failure",           to: "sessions#failure"
  delete "/logout",                 to: "sessions#destroy",  as: :logout

  # Team builder
  resource :team, only: [ :show ] do
    patch :update_slots, on: :member
  end
  get "/teams", to: "teams#index", as: :teams

  root "teams#show"
end
