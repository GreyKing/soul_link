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

  # Species assignment (drag-and-drop)
  resource :species, only: [ :show ], controller: "species_assignments" do
    patch :assign, on: :member
    patch :assign_from_pokedex, on: :member
  end

  # Gym readiness analysis
  resource :gym_ready, only: [ :show ], controller: "gym_ready"

  # Interactive region map
  resource :map, only: [ :show ], controller: "map"
  resources :pokemon_groups, only: [ :create ]
  resource :gym_progress, only: [ :update ], controller: "gym_progress"

  root "teams#show"
end
