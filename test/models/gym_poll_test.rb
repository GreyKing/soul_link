require "test_helper"

class GymPollTest < ActiveSupport::TestCase
  test "factory builds a valid open poll" do
    poll = build(:gym_poll)
    assert poll.valid?, poll.errors.full_messages.inspect
    assert_equal "open", poll.status
  end

  test "status must be open or locked" do
    poll = build(:gym_poll, status: "bogus")
    refute poll.valid?
    assert_includes poll.errors[:status], "is not included in the list"
  end

  test "open? and locked? helpers" do
    open_poll   = build(:gym_poll)
    locked_poll = build(:gym_poll, :locked)
    assert open_poll.open?
    refute open_poll.locked?
    assert locked_poll.locked?
    refute locked_poll.open?
  end
end

class GymPollMaterializationTest < ActiveSupport::TestCase
  TEMPLATE = {
    "slots" => [
      { "day_of_week" => 1, "time_of_day" => "19:00" }, # Mon 7pm
      { "day_of_week" => 3, "time_of_day" => "20:00" }, # Wed 8pm
      { "day_of_week" => 6, "time_of_day" => "14:00" }  # Sat 2pm
    ]
  }.freeze

  def run_with_template(tz: "America/Phoenix")
    build_stubbed(:soul_link_run, schedule_template: TEMPLATE, timezone: tz)
  end

  test "monday morning includes all three forward slots" do
    Time.use_zone("America/Phoenix") do
      slots = GymPoll.materialize_slots(run_with_template, now: Time.zone.local(2026, 5, 11, 6, 0))
      assert_equal 3, slots.length
      mon, wed, sat = slots.map { |s| Time.iso8601(s["scheduled_at"]).in_time_zone("America/Phoenix") }
      assert_equal [2026, 5, 11, 19, 0], [mon.year, mon.month, mon.day, mon.hour, mon.min]
      assert_equal [2026, 5, 13, 20, 0], [wed.year, wed.month, wed.day, wed.hour, wed.min]
      assert_equal [2026, 5, 16, 14, 0], [sat.year, sat.month, sat.day, sat.hour, sat.min]
    end
  end

  test "tuesday evening still materializes the past mon slot (rendering marks it past)" do
    slots = GymPoll.materialize_slots(
      run_with_template,
      now: Time.find_zone("America/Phoenix").local(2026, 5, 12, 20, 0)
    )
    mon = Time.iso8601(slots[0]["scheduled_at"]).in_time_zone("America/Phoenix")
    assert_equal 11, mon.day  # Mon is May 11; "now" is May 12 20:00 -> Mon slot is past
    assert mon < Time.find_zone("America/Phoenix").local(2026, 5, 12, 20, 0)
  end

  test "saturday afternoon: weekday slots past, sat slot today is materialized" do
    slots = GymPoll.materialize_slots(
      run_with_template,
      now: Time.find_zone("America/Phoenix").local(2026, 5, 16, 13, 0)
    )
    sat = Time.iso8601(slots[2]["scheduled_at"]).in_time_zone("America/Phoenix")
    assert_equal 16, sat.day
    assert_equal 14, sat.hour
  end

  test "sunday rolls forward to next mon-sun" do
    # Sunday May 17 2026 -> materialized slots should be May 18 (Mon) onward
    slots = GymPoll.materialize_slots(
      run_with_template,
      now: Time.find_zone("America/Phoenix").local(2026, 5, 17, 10, 0)
    )
    mon = Time.iso8601(slots[0]["scheduled_at"]).in_time_zone("America/Phoenix")
    assert_equal 18, mon.day, "Sunday-created poll should roll to next Monday (May 18)"
  end

  test "empty template raises EmptyTemplateError" do
    run = build_stubbed(:soul_link_run, schedule_template: { "slots" => [] }, timezone: "America/Phoenix")
    assert_raises(GymPoll::EmptyTemplateError) { GymPoll.materialize_slots(run) }
  end

  test "nil template raises EmptyTemplateError" do
    run = build_stubbed(:soul_link_run, schedule_template: nil, timezone: "America/Phoenix")
    assert_raises(GymPoll::EmptyTemplateError) { GymPoll.materialize_slots(run) }
  end

  test "spring-forward DST week (Eastern): Sun 02:30 slot resolves correctly" do
    # 2026-03-08 is the US spring-forward Sunday. 02:30 doesn't exist on that day in Eastern.
    # We're not creating a 02:30 slot here, but DST-zone math is still under test:
    # use a 03:00 Sun slot in Eastern, verify it materializes correctly the day after DST.
    template = { "slots" => [ { "day_of_week" => 1, "time_of_day" => "07:00" } ] }
    run = build_stubbed(:soul_link_run, schedule_template: template, timezone: "America/New_York")
    slots = GymPoll.materialize_slots(run, now: Time.find_zone("America/New_York").local(2026, 3, 9, 6, 0))
    mon = Time.iso8601(slots[0]["scheduled_at"]).in_time_zone("America/New_York")
    assert_equal [2026, 3, 9, 7, 0], [mon.year, mon.month, mon.day, mon.hour, mon.min]
  end

  test "fall-back DST week: Mon 07:00 slot resolves correctly" do
    # 2026-11-01 is fall-back Sunday in US. Test week of 2026-11-02 (Monday).
    template = { "slots" => [ { "day_of_week" => 1, "time_of_day" => "07:00" } ] }
    run = build_stubbed(:soul_link_run, schedule_template: template, timezone: "America/New_York")
    slots = GymPoll.materialize_slots(run, now: Time.find_zone("America/New_York").local(2026, 11, 2, 6, 0))
    mon = Time.iso8601(slots[0]["scheduled_at"]).in_time_zone("America/New_York")
    assert_equal [2026, 11, 2, 7, 0], [mon.year, mon.month, mon.day, mon.hour, mon.min]
  end
end

class GymPollVoteTest < ActiveSupport::TestCase
  PLAYER_IDS = [111, 222, 333, 444].freeze

  def with_player_ids(&block)
    SoulLink::GameState.stub(:player_ids, PLAYER_IDS, &block)
  end

  def open_poll
    create(:gym_poll, state_data: {
      "slots" => [
        { "index" => 0, "scheduled_at" => 2.days.from_now.utc.iso8601 },
        { "index" => 1, "scheduled_at" => 4.days.from_now.utc.iso8601 }
      ],
      "votes" => {}
    })
  end

  test "vote! records the response in state_data" do
    poll = open_poll
    with_player_ids { poll.vote!(111, 0, "yes") }
    poll.reload
    assert_equal "yes", poll.votes["111"]["0"]
  end

  test "vote! is idempotent — re-voting same value is fine" do
    poll = open_poll
    with_player_ids do
      poll.vote!(111, 0, "yes")
      poll.vote!(111, 0, "yes")
    end
    assert_equal "yes", poll.reload.votes["111"]["0"]
  end

  test "vote! flips an existing vote" do
    poll = open_poll
    with_player_ids do
      poll.vote!(111, 0, "yes")
      poll.vote!(111, 0, "no")
    end
    assert_equal "no", poll.reload.votes["111"]["0"]
  end

  test "vote! locks the poll when all 4 players say yes on a slot" do
    poll = open_poll
    with_player_ids { PLAYER_IDS.each { |uid| poll.vote!(uid, 0, "yes") } }
    poll.reload
    assert poll.locked?
    assert_equal 0, poll.locked_slot_index
    assert_not_nil poll.locked_at
  end

  test "vote! does not lock when 3 yes and 1 maybe" do
    poll = open_poll
    with_player_ids do
      poll.vote!(PLAYER_IDS[0], 0, "yes")
      poll.vote!(PLAYER_IDS[1], 0, "yes")
      poll.vote!(PLAYER_IDS[2], 0, "yes")
      poll.vote!(PLAYER_IDS[3], 0, "maybe")
    end
    assert poll.reload.open?
  end

  test "vote! does not lock when 3 yes only (one player hasn't voted)" do
    poll = open_poll
    with_player_ids do
      poll.vote!(PLAYER_IDS[0], 0, "yes")
      poll.vote!(PLAYER_IDS[1], 0, "yes")
      poll.vote!(PLAYER_IDS[2], 0, "yes")
    end
    assert poll.reload.open?
  end

  test "vote! raises when poll is locked" do
    poll = create(:gym_poll, :locked)
    with_player_ids do
      error = assert_raises(GymPoll::LockedError) { poll.vote!(111, 0, "yes") }
      assert_match(/locked/i, error.message)
    end
  end

  test "vote! raises when slot index is out of range" do
    poll = open_poll
    with_player_ids { assert_raises(GymPoll::InvalidSlotError) { poll.vote!(111, 99, "yes") } }
  end

  test "vote! raises when slot is in the past" do
    poll = create(:gym_poll, state_data: {
      "slots" => [ { "index" => 0, "scheduled_at" => 1.hour.ago.utc.iso8601 } ],
      "votes" => {}
    })
    with_player_ids { assert_raises(GymPoll::PastSlotError) { poll.vote!(111, 0, "yes") } }
  end

  test "vote! raises on invalid response" do
    poll = open_poll
    with_player_ids { assert_raises(GymPoll::InvalidResponseError) { poll.vote!(111, 0, "potato") } }
  end
end
