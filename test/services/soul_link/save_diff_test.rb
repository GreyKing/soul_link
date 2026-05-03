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

    # ── Step 17: party diff (catches + removals) ──────────────────────

    # Tiny helper for building party-entry hashes the way
    # ParseSaveDataJob persists them (PkmDecoder::Pkm#to_h).
    def pkm_h(pid:, species: 100, met_loc: 16, level: 5, ot_id: 1, ot_sid: 1, is_egg: false)
      { pid: pid, species: species, met_location_id: met_loc, level: level,
        ot_id: ot_id, ot_sid: ot_sid, is_egg: is_egg }
    end

    test "Step 17 backward compat: Step-15-style call returns empty catch/removal arrays" do
      result = SoulLink::SaveDiff.between(prev_badges: 0, curr_badges: 1)
      assert_equal [], result.catch_events
      assert_equal [], result.removal_events
    end

    test "empty prev + empty curr produces no catch / removal events" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: [], curr_party: []
      )
      assert_equal [], result.catch_events
      assert_equal [], result.removal_events
    end

    test "empty prev + 1 PKM curr → 1 PokemonCaughtEvent" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: [],
        curr_party: [ pkm_h(pid: 0xAAAA, species: 387, met_loc: 16, level: 5) ]
      )
      assert_equal 1, result.catch_events.size
      event = result.catch_events.first
      assert_kind_of SoulLink::SaveDiff::PokemonCaughtEvent, event
      assert_equal 0xAAAA, event.pid
      assert_equal 387,    event.species_id
      assert_equal 16,     event.met_location_id
      assert_equal 5,      event.level
      assert_equal [], result.removal_events
    end

    test "1 PKM prev + same 1 PKM curr → no events (PID stable)" do
      same = pkm_h(pid: 0xAAAA, species: 387, met_loc: 16)
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: [ same ], curr_party: [ same ]
      )
      assert_equal [], result.catch_events
      assert_equal [], result.removal_events
    end

    test "1 PKM prev + different PID curr → 1 catch + 1 removal" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: [ pkm_h(pid: 0xAAAA, species: 387) ],
        curr_party: [ pkm_h(pid: 0xBBBB, species: 100) ]
      )
      assert_equal 1, result.catch_events.size
      assert_equal 0xBBBB, result.catch_events.first.pid
      assert_equal 1, result.removal_events.size
      assert_equal 0xAAAA, result.removal_events.first.pid
    end

    test "6 prev + 5 curr (same 5 PIDs survived) → 1 removal" do
      shared = (1..5).map { |i| pkm_h(pid: 0x1000 + i, species: 100 + i) }
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: shared + [ pkm_h(pid: 0xDEAD, species: 999) ],
        curr_party: shared
      )
      assert_equal [], result.catch_events
      assert_equal 1, result.removal_events.size
      assert_equal 0xDEAD, result.removal_events.first.pid
    end

    test "both nil → no catch / removal events (defensive)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: nil, curr_party: nil
      )
      assert_equal [], result.catch_events
      assert_equal [], result.removal_events
    end

    test "only one side nil → no events (defensive)" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: nil, curr_party: [ pkm_h(pid: 0xAAAA) ]
      )
      assert_equal [], result.catch_events
      assert_equal [], result.removal_events
    end

    test "string-keyed entries (post-JSON-roundtrip) work the same as symbol-keyed" do
      str_entry = { "pid" => 0xCAFE, "species" => 50, "met_location_id" => 17,
                    "level" => 10, "ot_id" => 1, "ot_sid" => 1, "is_egg" => false }
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: [], curr_party: [ str_entry ]
      )
      assert_equal 1, result.catch_events.size
      assert_equal 0xCAFE, result.catch_events.first.pid
      assert_equal 50,     result.catch_events.first.species_id
      assert_equal 17,     result.catch_events.first.met_location_id
    end

    test "Result#empty? is false when only catch events are present" do
      result = SoulLink::SaveDiff.between(
        prev_badges: 0, curr_badges: 0,
        prev_party: [], curr_party: [ pkm_h(pid: 0xAAAA) ]
      )
      assert_not result.empty?
    end
  end
end
