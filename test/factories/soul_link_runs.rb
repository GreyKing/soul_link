FactoryBot.define do
  factory :soul_link_run do
    guild_id { 999999999999999999 }
    # Start above existing fixture run_numbers (active_run uses 1) so the
    # `(guild_id, run_number)` uniqueness constraint never collides with
    # legacy fixtures that load alongside factory-built records.
    sequence(:run_number) { |n| 1000 + n }
    active { true }

    trait :with_schedule_template do
      schedule_template do
        {
          "slots" => [
            { "day_of_week" => 1, "time_of_day" => "19:00" },
            { "day_of_week" => 3, "time_of_day" => "20:00" },
            { "day_of_week" => 6, "time_of_day" => "14:00" }
          ]
        }
      end
    end

    trait :in_eastern_time do
      timezone { "America/New_York" }
    end
  end
end
