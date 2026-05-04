require "test_helper"

module SoulLink
  class CatchCoordinatorTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      @session = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: 1001)
      @slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1,
                     parsed_trainer_id: 0xABCD, parsed_secret_id: 0x1234, parsed_at: 1.minute.ago)
      @session.update!(active_save_slot: 1)
      SoulLink::CatchCoordinator.reset_species_cache!
    end

    def caught_event(overrides = {})
      defaults = {
        pid: 0xDEADBEEF, species_id: 387, met_location_id: 16,
        level: 5, ot_id: 0xABCD, ot_sid: 0x1234, is_egg: false,
        nature: nil, ivs: nil, evs: nil, moves: nil
      }
      SoulLink::SaveDiff::PokemonCaughtEvent.new(**defaults.merge(overrides))
    end

    test "no-op on empty events array" do
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [])
      end
    end

    test "no-op on nil events" do
      assert_nothing_raised do
        SoulLink::CatchCoordinator.process(@slot, nil)
      end
    end

    test "no-op when slot is nil" do
      assert_nothing_raised do
        SoulLink::CatchCoordinator.process(nil, [ caught_event ])
      end
    end

    test "no-op when slot has no session (defensive — bare AR object)" do
      # A SoulLinkEmulatorSaveSlot with no session shouldn't blow up; the
      # `session = slot&.soul_link_emulator_session` chain returns nil
      # and we early-return.
      bare_slot = SoulLinkEmulatorSaveSlot.new
      bare_slot.define_singleton_method(:soul_link_emulator_session) { nil }
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(bare_slot, [ caught_event ])
      end
    end

    test "no-op when session has no discord_user_id (unclaimed)" do
      @session.update!(discord_user_id: nil)
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      end
    end

    test "egg event is silently dropped" do
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(is_egg: true) ])
      end
    end

    test "zero-PID event is silently dropped" do
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(pid: 0) ])
      end
    end

    test "PokemonRemovedEvent is log-only, no AR side effect" do
      removed = SoulLink::SaveDiff::PokemonRemovedEvent.new(pid: 0xAAAAAAAA)
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ removed ])
      end
    end

    test "new catch creates a SoulLinkPokemon row with the right fields" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      end
      row = SoulLinkPokemon.last
      assert_equal @run.id,           row.soul_link_run_id
      assert_equal 1001,              row.discord_user_id
      assert_nil   row.soul_link_pokemon_group_id
      assert_equal 0xDEADBEEF,        row.pid
      assert_equal 16,                row.met_location_id
      assert_equal "Route 201",       row.location
      assert_equal 5,                 row.level
      assert_equal 0xABCD,            row.ot_id
      assert_equal 0x1234,            row.ot_sid
      assert_equal false,             row.trade_in
      assert_equal "catch",           row.acquired_via
      assert_equal "caught",          row.status
    end

    test "duplicate PID for the same (run, player) is no-op (idempotency)" do
      SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])  # same PID
      end
    end

    test "duplicate PID across DIFFERENT runs is allowed (cross-run unique scope)" do
      SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      # Use a different guild_id to dodge the active-run-per-guild
      # uniqueness invariant (Step 11 partial unique index).
      other_run = create(:soul_link_run, guild_id: 8888888888888888888, run_number: 9999)
      other_session = create(:soul_link_emulator_session, :ready,
                             soul_link_run: other_run, discord_user_id: 1001,
                             active_save_slot: 1)
      other_slot = create(:soul_link_emulator_save_slot,
                          soul_link_emulator_session: other_session, slot_number: 1,
                          parsed_trainer_id: 0xABCD, parsed_secret_id: 0x1234, parsed_at: 1.minute.ago)
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(other_slot, [ caught_event ])
      end
    end

    test "trade-in: ot_id/ot_sid differ from slot's parsed TID/SID → trade_in true + acquired_via 'trade_in'" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(ot_id: 0xFFFF, ot_sid: 0xEEEE) ])
      end
      row = SoulLinkPokemon.last
      assert_equal true, row.trade_in
      assert_equal "trade_in", row.acquired_via
    end

    test "event-met-location: met_id flagged event:true → acquired_via 'event_gift'" do
      # Met-location 2002 = LinkTrade4 (event:true in met_locations.yml).
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(met_location_id: 2002) ])
      end
      row = SoulLinkPokemon.last
      assert_equal "event_gift", row.acquired_via
      assert_equal "Link Trade", row.location
    end

    test "unknown met_location_id falls back to 'Met-Location #N'" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(met_location_id: 9999) ])
      end
      assert_equal "Met-Location #9999", SoulLinkPokemon.last.location
    end

    test "event_gift takes precedence over trade_in flag for acquired_via classification" do
      # Daycare ID (2000, event:true). Even though TID/SID match, the
      # met-location flag wins for acquired_via classification.
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(met_location_id: 2000) ])
      end
      assert_equal "event_gift", SoulLinkPokemon.last.acquired_via
    end

    test "transaction wraps creates — raise mid-loop rolls back the partial create" do
      events = [ caught_event(pid: 0xAAAA1111), caught_event(pid: 0xBBBB2222) ]
      # Stub the SECOND create to raise. We expect the first create to roll back.
      original_create = SoulLinkPokemon.method(:create!)
      call_count = 0
      stub = ->(*args) {
        call_count += 1
        raise StandardError, "boom" if call_count == 2
        original_create.call(*args)
      }
      SoulLinkPokemon.stub(:create!, stub) do
        assert_no_difference "SoulLinkPokemon.count" do
          assert_raises(StandardError) do
            SoulLink::CatchCoordinator.process(@slot, events)
          end
        end
      end
    end

    test "trade_in defaults false when slot has no parsed TID/SID yet" do
      @slot.update_columns(parsed_trainer_id: 0, parsed_secret_id: 0)
      # Even though event TID/SID differ from 0/0, with no baseline we
      # don't false-positive a trade-in.
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(ot_id: 0xFFFF, ot_sid: 0xEEEE) ])
      end
      assert_equal false, SoulLinkPokemon.last.trade_in
    end

    # ── Step 18: per-Pokémon stats persistence ────────────────────────

    test "Step 18: PokemonCaughtEvent persists nature / ivs / evs / moves columns" do
      ivs = { hp: 31, atk: 31, def: 31, spe: 31, spa: 31, spd: 31 }
      evs = { hp: 252, atk: 0, def: 4, spe: 252, spa: 0, spd: 0 }
      moves = [ { id: 1, pp: 35, pp_up: 0 }, { id: 84, pp: 30, pp_up: 1 },
                { id: 0,  pp: 0,  pp_up: 0 }, { id: 0,  pp: 0,  pp_up: 0 } ]
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event(
          pid: 0x1A1A1A1A,  # 0x1A1A1A1A % 25 = 22 → Sassy
          nature: 22, ivs: ivs, evs: evs, moves: moves
        ) ])
      end
      row = SoulLinkPokemon.last
      assert_equal "Sassy", row.nature
      # JSON read-back gives string-keyed hashes regardless of how we wrote them.
      assert_equal({ "hp" => 31, "atk" => 31, "def" => 31, "spe" => 31, "spa" => 31, "spd" => 31 }, row.ivs)
      assert_equal({ "hp" => 252, "atk" => 0, "def" => 4, "spe" => 252, "spa" => 0, "spd" => 0 }, row.evs)
      assert_equal 4, row.moves.size
      assert_equal 1, row.moves[0]["id"]
      assert_equal false, row.caught_off_feed
    end

    test "Step 18: PokemonCaughtEvent without nature/ivs/evs/moves keeps columns nil (back-compat)" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])  # no nature/ivs/evs/moves
      end
      row = SoulLinkPokemon.last
      assert_nil row.nature
      assert_nil row.ivs
      assert_nil row.evs
      assert_nil row.moves
      assert_equal false, row.caught_off_feed
    end

    def boxed_event(overrides = {})
      defaults = {
        pid: 0xBADBEEF1, species_id: 387, met_location_id: 16,
        level: nil, ot_id: 0xABCD, ot_sid: 0x1234, is_egg: false,
        nature: 0, ivs: nil, evs: nil, moves: nil
      }
      SoulLink::SaveDiff::BoxedPokemonObservedEvent.new(**defaults.merge(overrides))
    end

    test "Step 18: BoxedPokemonObservedEvent for a new PID creates row with caught_off_feed: true" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event ])
      end
      row = SoulLinkPokemon.last
      assert_equal 0xBADBEEF1, row.pid
      assert_equal "catch", row.acquired_via
      assert_equal true, row.caught_off_feed
    end

    test "Step 18: BoxedPokemonObservedEvent for a PID already in DB is no-op (existing dedup)" do
      # Seed a party-side row first.
      SoulLink::CatchCoordinator.process(@slot, [ caught_event(pid: 0xBABEFACE) ])
      assert_equal 1, SoulLinkPokemon.count

      # Now a box event arrives for the same PID. Should no-op.
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event(pid: 0xBABEFACE) ])
      end
      # caught_off_feed remains false (party-side won).
      assert_equal false, SoulLinkPokemon.find_by(pid: 0xBABEFACE).caught_off_feed
    end

    test "Step 18: same-snapshot PokemonCaughtEvent + BoxedPokemonObservedEvent for same PID creates exactly one row" do
      # Critical test — covers the cross-event collision case the brief calls out.
      # Order matches dispatcher: catch_events first, then box_events.
      pid = 0xC0FFEE01
      events = [
        caught_event(pid: pid),
        boxed_event(pid: pid)
      ]
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, events)
      end
      row = SoulLinkPokemon.find_by(pid: pid)
      # Party-side wins because it processes first; caught_off_feed: false.
      assert_equal false, row.caught_off_feed
      assert_equal "catch", row.acquired_via
    end

    test "Step 18: BoxedPokemonObservedEvent — egg met_location → acquired_via 'event_gift'" do
      # 2002 = LinkTrade4 (event:true).
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event(met_location_id: 2002) ])
      end
      row = SoulLinkPokemon.last
      assert_equal "event_gift", row.acquired_via
      assert_equal true, row.caught_off_feed
    end

    test "Step 18: BoxedPokemonObservedEvent — trade-in (different OT) → trade_in true + acquired_via 'trade_in'" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event(ot_id: 0xFFFF, ot_sid: 0xEEEE) ])
      end
      row = SoulLinkPokemon.last
      assert_equal true, row.trade_in
      assert_equal "trade_in", row.acquired_via
      assert_equal true, row.caught_off_feed
    end

    test "Step 18: BoxedPokemonObservedEvent — egg event silently dropped" do
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event(is_egg: true) ])
      end
    end

    test "Step 18: BoxedPokemonObservedEvent — zero PID silently dropped" do
      assert_no_difference "SoulLinkPokemon.count" do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event(pid: 0) ])
      end
    end

    test "Step 18: nil nature is not coerced to a string (column stays nil)" do
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event(nature: nil) ])
      end
      assert_nil SoulLinkPokemon.last.nature
    end

    test "Step 18: caught_event helper without overrides creates row with caught_off_feed: false" do
      # Locks the contract that handle_caught explicitly passes false
      # (column is NOT NULL in DB).
      assert_difference "SoulLinkPokemon.count", 1 do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      end
      assert_equal false, SoulLinkPokemon.last.caught_off_feed
    end

    # ── Step 19: DiscordNotifier wiring ──────────────────────────────

    test "Step 19: happy-path catch fires notify_catch with off_feed: false" do
      calls = []
      recorder = ->(*args, **kwargs) { calls << [ args, kwargs ] }
      SoulLink::DiscordNotifier.stub(:notify_catch, recorder) do
        SoulLink::CatchCoordinator.process(@slot, [ caught_event ])
      end
      assert_equal 1, calls.size
      kwargs = calls.first[1]
      assert_equal false, kwargs[:off_feed]
    end

    test "Step 19: box-observed catch fires notify_catch with off_feed: true" do
      calls = []
      recorder = ->(*args, **kwargs) { calls << [ args, kwargs ] }
      SoulLink::DiscordNotifier.stub(:notify_catch, recorder) do
        SoulLink::CatchCoordinator.process(@slot, [ boxed_event ])
      end
      assert_equal 1, calls.size
      kwargs = calls.first[1]
      assert_equal true, kwargs[:off_feed]
    end

    test "Step 18: PokemonCaughtEvent struct accepts the new keyword fields" do
      # Lock the Struct contract — new fields are keyword-init, not raise.
      ev = SoulLink::SaveDiff::PokemonCaughtEvent.new(
        pid: 1, species_id: 1, met_location_id: 1, level: 1, ot_id: 1, ot_sid: 1, is_egg: false,
        nature: 5, ivs: { hp: 1 }, evs: { hp: 2 }, moves: [ { id: 1 } ]
      )
      assert_equal 5,           ev.nature
      assert_equal({ hp: 1 },   ev.ivs)
      assert_equal({ hp: 2 },   ev.evs)
      assert_equal([ { id: 1 } ], ev.moves)
    end
  end
end
