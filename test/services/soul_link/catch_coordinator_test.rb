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
        level: 5, ot_id: 0xABCD, ot_sid: 0x1234, is_egg: false
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
  end
end
