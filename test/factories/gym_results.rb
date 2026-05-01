# Mirrors `test/fixtures/gym_results.yml` (empty — fixture is a comment
# placeholder) — Step 4 of the FactoryBot conversion plan. Provides the
# minimum-viable defaults needed to pass model validations:
# `gym_number` (1..8, unique per run) and `beaten_at` (present). The
# sequence on `gym_number` cycles 1..8 so successive `create(:gym_result)`
# calls against the same run don't collide on the
# `(soul_link_run_id, gym_number)` uniqueness constraint until the 9th
# call — well past the needs of any single test.
FactoryBot.define do
  factory :gym_result do
    association :soul_link_run
    sequence(:gym_number) { |n| ((n - 1) % 8) + 1 }
    beaten_at { Time.current }
  end
end
