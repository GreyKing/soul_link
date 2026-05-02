# Per-(run, gym_number) suppression record. The sequence on
# `gym_number` cycles 1..8 so successive `create(:gym_auto_mark_suppression)`
# calls against the same run don't collide on the
# `(soul_link_run_id, gym_number)` uniqueness constraint until the 9th
# call — well past the needs of any single test.
FactoryBot.define do
  factory :gym_auto_mark_suppression do
    association :soul_link_run
    sequence(:gym_number) { |n| ((n - 1) % 8) + 1 }
  end
end
