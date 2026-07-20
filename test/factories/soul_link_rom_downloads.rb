FactoryBot.define do
  factory :soul_link_rom_download do
    association :soul_link_run
    # Must be a REGISTERED player (GameState.players.first) — the controller
    # scopes downloads to current_user_id, and the controller tests log in as
    # that player. A sequence here would break them.
    discord_user_id { SoulLink::GameState.players.first["discord_user_id"] }
    status { "pending" }
  end
end
