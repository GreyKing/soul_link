FactoryBot.define do
  factory :soul_link_emulator_session do
    association :soul_link_run
    status { "pending" }
    sequence(:seed) { |n| "seed-#{n}" }
    discord_user_id { nil }
    rom_path { nil }

    trait :ready do
      status { "ready" }
      rom_path { "storage/roms/randomized/test/seed.nds" }
    end

    trait :claimed do
      sequence(:discord_user_id) { |n| 153665622641737728 + n }
    end

    trait :generating do
      status { "generating" }
      rom_path { nil }
    end
  end
end
