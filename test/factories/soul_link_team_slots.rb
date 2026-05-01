# Mirrors `test/fixtures/soul_link_team_slots.yml` — Step 4 of the
# FactoryBot conversion plan. Fixture has two entries (`grey_slot_1`,
# `grey_slot_2`). Per the brief, the team + group associations are passed
# by the test caller (no factory defaults), since slot rows are only
# meaningful in the context of a specific team and pokemon group set up
# elsewhere in the test.
FactoryBot.define do
  factory :soul_link_team_slot do
    trait :slot_1 do
      position { 1 }
    end

    trait :slot_2 do
      position { 2 }
    end
  end
end
