# Mirrors `test/fixtures/gym_drafts.yml` — Step 4 of the FactoryBot
# conversion plan. The model's `after_initialize :set_defaults` already
# populates `state_data` and `pick_order` to match the fixture's lobby
# state, so the base factory only needs to provide the run association
# and rely on those defaults. The `:lobby` trait pins those values
# explicitly to keep the trait's intent self-documenting.
FactoryBot.define do
  factory :gym_draft do
    association :soul_link_run
    status { "lobby" }
    current_round { 0 }
    current_player_index { 0 }
    pick_order { [] }
    state_data { { "ready_players" => [], "first_pick_votes" => {}, "picks" => [] } }

    trait :lobby do
      status { "lobby" }
      current_round { 0 }
      current_player_index { 0 }
      pick_order { [] }
      state_data { { "ready_players" => [], "first_pick_votes" => {}, "picks" => [] } }
    end
  end
end
