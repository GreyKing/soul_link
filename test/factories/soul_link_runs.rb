FactoryBot.define do
  factory :soul_link_run do
    guild_id { 999999999999999999 }
    # Start above existing fixture run_numbers (active_run uses 1) so the
    # `(guild_id, run_number)` uniqueness constraint never collides with
    # legacy fixtures that load alongside factory-built records.
    sequence(:run_number) { |n| 1000 + n }
    active { true }
  end
end
