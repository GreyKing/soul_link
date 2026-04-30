FactoryBot.define do
  factory :soul_link_emulator_save_slot do
    association :soul_link_emulator_session
    sequence(:slot_number) { |n| ((n - 1) % SoulLinkEmulatorSaveSlot::MAX_SLOT) + SoulLinkEmulatorSaveSlot::MIN_SLOT }
    save_data { nil }

    trait :filled do
      save_data { "PLATINUM_SRAM_BYTES_\x00\x01\x02".b }
    end

    trait :parsed do
      parsed_trainer_name { "Lyra" }
      parsed_money { 12_345 }
      parsed_play_seconds { 3_600 }
      parsed_badges { 4 }
      parsed_map_id { 42 }
      parsed_at { Time.current }
    end
  end
end
