FactoryBot.define do
  factory :gym_schedule do
    association :soul_link_run
    proposed_by { 153665622641737728 }
    scheduled_at { 1.day.from_now }
    status { "proposed" }
  end
end
