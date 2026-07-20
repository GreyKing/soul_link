Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Discord OAuth
  get    "/login",                  to: "sessions#new",     as: :login
  post   "/auth/discord/callback",  to: "sessions#create"
  get    "/auth/discord/callback",  to: "sessions#create"
  get    "/auth/failure",           to: "sessions#failure"
  delete "/logout",                 to: "sessions#destroy",  as: :logout

  # API endpoints (JSON)
  namespace :api do
    resources :pokemon, only: [ :show ], param: :species
    post "calculator", to: "calculator#calculate"
  end

  # Team builder
  resource :team, only: [ :show ] do
    patch :update_slots, on: :member
  end
  get "/teams", to: "teams#index", as: :teams

  # Species assignment (drag-and-drop)
  resource :species, only: [ :show ], controller: "species_assignments" do
    patch :assign, on: :member
    patch :assign_from_pokedex, on: :member
    patch :unassign, on: :member
  end

  # Player dashboard
  resource :dashboard, only: [ :show ], controller: "dashboard"

  # Gym readiness analysis + gym draft
  resource :gym_ready, only: [ :show ], controller: "gym_ready"
  resources :gym_drafts, only: [ :create, :show, :destroy ] do
    member { post :mark_beaten }
  end
  resources :gym_results, only: [ :update ]
  # Run management
  resources :runs, only: %i[index edit update] do
    resources :rom_downloads, only: %i[create show], module: :runs do
      get :download, on: :member
    end
  end

  # Singleton poll: one open/locked poll per run at a time
  resource :gym_poll, only: %i[show create destroy], controller: "gym_polls"

  # Player-facing emulator (auto-claims one of the run's randomized ROMs)
  resource :emulator, only: [ :show ], controller: "emulator" do
    get    :rom
    get    :save_data
    delete :save_data         # wipes ALL slots for the player's session
    get    :firmware
    resources :save_slots, only: [ :index, :create, :update, :destroy ], param: :slot_number do
      member do
        post :restore
        get  :download
      end
    end
  end

  # Interactive region map
  resource :map, only: [ :show ], controller: "map"
  resources :pokemon_groups, only: [ :create, :update, :destroy ] do
    patch :reorder, on: :collection
  end
  resources :pokemon, only: [ :create, :update ], controller: "pokemon"
  resource :gym_progress, only: [ :update ], controller: "gym_progress"

  root "dashboard#show"
end
