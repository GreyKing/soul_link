FactoryBot.define do
  factory :gym_poll do
    association :soul_link_run
    status { "open" }
    state_data do
      {
        "slots" => [
          { "index" => 0, "scheduled_at" => 2.days.from_now.utc.iso8601 },
          { "index" => 1, "scheduled_at" => 4.days.from_now.utc.iso8601 }
        ],
        "votes" => {}
      }
    end

    trait :locked do
      status { "locked" }
      locked_slot_index { 0 }
      locked_at { Time.current }
    end

    trait :pinged do
      locked
      pinged_at { Time.current }
    end
  end
end
