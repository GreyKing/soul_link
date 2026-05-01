# Mirrors `test/fixtures/soul_link_teams.yml` — Step 4 of the FactoryBot
# conversion plan. Fixture has one entry (`grey_team`); base factory uses
# a sequence for IDs so multi-team tests don't collide on the
# `(soul_link_run_id, discord_user_id)` uniqueness constraint.
FactoryBot.define do
  factory :soul_link_team do
    association :soul_link_run
    sequence(:discord_user_id) { |n| 153665622641737728 + n }

    trait :grey_team do
      discord_user_id { 153665622641737728 }
    end
  end
end
