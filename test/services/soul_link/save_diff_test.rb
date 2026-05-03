require "test_helper"

module SoulLink
  class SaveDiffTest < ActiveSupport::TestCase
    test "nil prev returns empty result" do
      result = SoulLink::SaveDiff.between(prev_badges: nil, curr_badges: 5)
      assert_kind_of SoulLink::SaveDiff::Result, result
      assert_equal [], result.badge_events
      assert result.empty?
    end

    test "nil curr returns empty result" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: nil)
      assert_equal [], result.badge_events
      assert result.empty?
    end

    test "equal values return empty result" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 3)
      assert_equal [], result.badge_events
      assert result.empty?
    end

    test "+1 badge produces one BadgeGained event" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 4)
      assert_equal 1, result.badge_events.size
      event = result.badge_events.first
      assert_kind_of SoulLink::SaveDiff::BadgeGained, event
      assert_equal 4, event.gym_number
    end

    test "+2 badges produces two BadgeGained events in sequential order" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 5)
      assert_equal 2, result.badge_events.size
      assert(result.badge_events.all? { |e| e.is_a?(SoulLink::SaveDiff::BadgeGained) })
      assert_equal [ 4, 5 ], result.badge_events.map(&:gym_number)
    end

    test "-1 badge produces one BadgeLost event" do
      result = SoulLink::SaveDiff.between(prev_badges: 5, curr_badges: 4)
      assert_equal 1, result.badge_events.size
      event = result.badge_events.first
      assert_kind_of SoulLink::SaveDiff::BadgeLost, event
      assert_equal 5, event.gym_number
    end

    test "full reset prev=8 curr=0 produces 8 BadgeLost events" do
      result = SoulLink::SaveDiff.between(prev_badges: 8, curr_badges: 0)
      assert_equal 8, result.badge_events.size
      assert(result.badge_events.all? { |e| e.is_a?(SoulLink::SaveDiff::BadgeLost) })
      assert_equal (1..8).to_a, result.badge_events.map(&:gym_number)
    end

    test "full claim prev=0 curr=8 produces 8 BadgeGained events" do
      result = SoulLink::SaveDiff.between(prev_badges: 0, curr_badges: 8)
      assert_equal 8, result.badge_events.size
      assert(result.badge_events.all? { |e| e.is_a?(SoulLink::SaveDiff::BadgeGained) })
      assert_equal (1..8).to_a, result.badge_events.map(&:gym_number)
    end

    # ── Step 16 backward-compat ───────────────────────────────────────────

    test "Step-15 call signature returns a Result with all 4 event arrays populated" do
      result = SoulLink::SaveDiff.between(prev_badges: 0, curr_badges: 1)

      assert_equal 1, result.badge_events.size
      assert_kind_of SoulLink::SaveDiff::BadgeGained, result.badge_events.first
      assert_equal 1, result.badge_events.first.gym_number
      # The new dimensions default to [].
      assert_equal [], result.tid_events
      assert_equal [], result.pokedex_events
      assert_equal [], result.hof_events
      assert_not result.empty?
    end

    test "Result#empty? is true when every dimension is empty" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 3)
      assert result.empty?
    end

    # ── Step 16: TidObserved ──────────────────────────────────────────────

    test "TidObserved fires on prev nil → curr present-and-nonzero" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_tid: nil, curr_tid: 1234,
        prev_sid: nil, curr_sid: 5678
      )
      assert_equal 1, result.tid_events.size
      event = result.tid_events.first
      assert_kind_of SoulLink::SaveDiff::TidObserved, event
      assert_equal 1234, event.trainer_id
      assert_equal 5678, event.secret_id
    end

    test "TidObserved does not fire when (prev TID, prev SID) == (curr TID, curr SID)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_tid: 1234, curr_tid: 1234,
        prev_sid: 5678, curr_sid: 5678
      )
      assert_equal [], result.tid_events
    end

    test "TidObserved fires when only TID changes (mix-up signal)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_tid: 1234, curr_tid: 9999,
        prev_sid: 5678, curr_sid: 5678
      )
      assert_equal 1, result.tid_events.size
      assert_equal 9999, result.tid_events.first.trainer_id
    end

    test "TidObserved is suppressed when curr_tid is zero (slot not parsed yet)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_tid: nil,  curr_tid: 0,
        prev_sid: nil,  curr_sid: 0
      )
      assert_equal [], result.tid_events
    end

    test "TidObserved is suppressed when curr_tid is nil (defensive)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_tid: 1234, curr_tid: nil,
        prev_sid: 5678, curr_sid: nil
      )
      assert_equal [], result.tid_events
    end

    # ── Step 16: PokedexProgress ──────────────────────────────────────────

    test "PokedexProgress does not fire when caught and seen are unchanged" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_pokedex_caught: 47, curr_pokedex_caught: 47,
        prev_pokedex_seen:   89, curr_pokedex_seen:   89
      )
      assert_equal [], result.pokedex_events
    end

    test "PokedexProgress fires once when caught changes (carries deltas + curr counts)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_pokedex_caught: 47, curr_pokedex_caught: 52,
        prev_pokedex_seen:   89, curr_pokedex_seen:   89
      )
      assert_equal 1, result.pokedex_events.size
      event = result.pokedex_events.first
      assert_kind_of SoulLink::SaveDiff::PokedexProgress, event
      assert_equal 5,  event.caught_delta
      assert_equal 0,  event.seen_delta
      assert_equal 52, event.curr_caught
      assert_equal 89, event.curr_seen
    end

    test "PokedexProgress allows negative deltas (older save load)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_pokedex_caught: 50, curr_pokedex_caught: 48,
        prev_pokedex_seen:   80, curr_pokedex_seen:   80
      )
      assert_equal 1, result.pokedex_events.size
      assert_equal(-2, result.pokedex_events.first.caught_delta)
    end

    test "PokedexProgress is suppressed when prev side is nil (defensive)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_pokedex_caught: nil, curr_pokedex_caught: 47,
        prev_pokedex_seen:   nil, curr_pokedex_seen:   89
      )
      assert_equal [], result.pokedex_events
    end

    # ── Step 16: HallOfFameEntered ────────────────────────────────────────

    test "HallOfFameEntered fires on prev nil → curr 1 transition" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_hof_count: nil, curr_hof_count: 1
      )
      assert_equal 1, result.hof_events.size
      assert_kind_of SoulLink::SaveDiff::HallOfFameEntered, result.hof_events.first
      assert_equal 1, result.hof_events.first.hof_count
    end

    test "HallOfFameEntered fires on prev 0 → curr 1 transition" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_hof_count: 0, curr_hof_count: 1
      )
      assert_equal 1, result.hof_events.size
    end

    test "HallOfFameEntered does not fire on prev 1 → curr 2 (repeat clears are not run-completion)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_hof_count: 1, curr_hof_count: 2
      )
      assert_equal [], result.hof_events
    end

    test "HallOfFameEntered does not fire on prev 1 → curr 1 (no transition)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_hof_count: 1, curr_hof_count: 1
      )
      assert_equal [], result.hof_events
    end

    test "HallOfFameEntered does not fire when curr is nil" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_hof_count: 0, curr_hof_count: nil
      )
      assert_equal [], result.hof_events
    end
  end
end
