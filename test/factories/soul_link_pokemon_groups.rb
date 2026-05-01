# Mirrors `test/fixtures/soul_link_pokemon_groups.yml` — Step 4 of the
# FactoryBot conversion plan. Fixture entries are inserted via raw SQL and
# bypass `before_create :set_position` / `:set_caught_at` callbacks; the
# `after(:create)` `update_columns` calls in each trait reproduce that
# raw-write behavior so trait records match the fixture row-for-row.
FactoryBot.define do
  factory :soul_link_pokemon_group do
    association :soul_link_run
    status { "caught" }
    sequence(:nickname) { |n| "GROUP#{n}" }
    sequence(:location) { |n| "route_#{200 + n}" }

    SOUL_LINK_POKEMON_GROUP_TRAITS = [
      { key: :route201, nickname: "ROY",    location: "route_201", position: 1, days_ago: 6 },
      { key: :route202, nickname: "TOMMY",  location: "route_202", position: 2, days_ago: 5 },
      { key: :route203, nickname: "RACHEL", location: "route_203", position: 3, days_ago: 4 },
      { key: :route204, nickname: "SPIKE",  location: "route_204", position: 4, days_ago: 3 },
      { key: :route205, nickname: "LUNA",   location: "route_205", position: 5, days_ago: 2 },
      { key: :route206, nickname: "BLAZE",  location: "route_206", position: 6, days_ago: 1 }
    ].freeze

    SOUL_LINK_POKEMON_GROUP_TRAITS.each do |spec|
      trait spec[:key] do
        nickname { spec[:nickname] }
        location { spec[:location] }
        status { "caught" }

        after(:create) do |record|
          record.update_columns(
            position: spec[:position],
            caught_at: spec[:days_ago].days.ago
          )
        end
      end
    end
  end
end
