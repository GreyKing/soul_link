require "test_helper"

class SoulLinkRunScheduleTest < ActiveSupport::TestCase
  test "timezone defaults to America/Phoenix" do
    run = create(:soul_link_run)
    assert_equal "America/Phoenix", run.timezone
  end

  test "timezone must be a recognized IANA zone" do
    run = build(:soul_link_run, timezone: "Not/A/Zone")
    refute run.valid?
    assert_includes run.errors[:timezone], "is not a recognized time zone"
  end

  test "with_schedule_template trait persists round-trip" do
    run = create(:soul_link_run, :with_schedule_template)
    assert_equal 3, run.schedule_template["slots"].length
    assert_equal 1, run.schedule_template["slots"].first["day_of_week"]
  end

  test "schedule_template defaults to nil" do
    assert_nil create(:soul_link_run).schedule_template
  end

  test "schedule_template validation: rejects malformed slot (missing day_of_week)" do
    run = build(:soul_link_run, schedule_template: { "slots" => [ { "time_of_day" => "19:00" } ] })
    refute run.valid?
    assert_includes run.errors[:schedule_template].first, "day_of_week"
  end

  test "schedule_template validation: rejects malformed slot (bad time_of_day format)" do
    run = build(:soul_link_run, schedule_template: { "slots" => [ { "day_of_week" => 1, "time_of_day" => "7pm" } ] })
    refute run.valid?
    assert_includes run.errors[:schedule_template].first, "time_of_day"
  end

  test "schedule_template validation: rejects more than 5 slots" do
    slots = 6.times.map { |i| { "day_of_week" => 1, "time_of_day" => "19:00" } }
    run = build(:soul_link_run, schedule_template: { "slots" => slots })
    refute run.valid?
    assert_includes run.errors[:schedule_template].first, "max 5"
  end
end
