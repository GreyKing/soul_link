require "test_helper"

module SoulLink
  class SaveDiffDispatcherTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      @session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
      @slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    end

    def baseline_state(parsed_at: 1.minute.ago)
      {
        parsed_at:      parsed_at,
        badges:         0,
        trainer_id:     0,
        secret_id:      0,
        pokedex_caught: 0,
        pokedex_seen:   0,
        hof_count:      0,
        party_data:     nil,
        box_data:       nil
      }
    end

    # Stub all five coordinators with a no-op closure that records each
    # call. Yields the +calls+ Hash so the test body can inspect it.
    def with_stubbed_coordinators
      calls = { gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }
      gym  = ->(*_args) { calls[:gym]     += 1 }
      tid  = ->(*_args) { calls[:tid]     += 1 }
      dex  = ->(*_args) { calls[:pokedex] += 1 }
      hof  = ->(*_args) { calls[:hof]     += 1 }
      cch  = ->(*_args) { calls[:catch]   += 1 }
      SoulLink::GymBeatenCoordinator.stub(:process, gym) do
        SoulLink::TidObservationCoordinator.stub(:process, tid) do
          SoulLink::PokedexProgressCoordinator.stub(:process, dex) do
            SoulLink::HallOfFameCoordinator.stub(:process, hof) do
              SoulLink::CatchCoordinator.stub(:process, cch) do
                yield calls
              end
            end
          end
        end
      end
    end

    # ── baseline rule (Step 15 → Step 16 carry-over) ──────────────────────

    test "first-ever parse (prev[:parsed_at] nil) does not call any coordinator" do
      prev = baseline_state(parsed_at: nil)
      curr = baseline_state(parsed_at: Time.current).merge(badges: 5, trainer_id: 1234, hof_count: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    test "empty diff (every value equal) does not call any coordinator" do
      prev = baseline_state.merge(badges: 3, trainer_id: 1234, secret_id: 5678,
                                  pokedex_caught: 47, pokedex_seen: 89, hof_count: 0)
      curr = baseline_state.merge(badges: 3, trainer_id: 1234, secret_id: 5678,
                                  pokedex_caught: 47, pokedex_seen: 89, hof_count: 0)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    # ── per-category dispatch ─────────────────────────────────────────────

    test "BadgeGained event only invokes GymBeatenCoordinator" do
      prev = baseline_state.merge(badges: 0)
      curr = baseline_state.merge(badges: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 1, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    test "TidObserved event only invokes TidObservationCoordinator" do
      prev = baseline_state.merge(trainer_id: 0, secret_id: 0)
      curr = baseline_state.merge(trainer_id: 1234, secret_id: 5678)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 1, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    test "PokedexProgress event only invokes PokedexProgressCoordinator" do
      prev = baseline_state.merge(pokedex_caught: 47, pokedex_seen: 89)
      curr = baseline_state.merge(pokedex_caught: 50, pokedex_seen: 92)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 1, hof: 0, catch: 0 }, calls)
      end
    end

    test "HallOfFameEntered event only invokes HallOfFameCoordinator" do
      prev = baseline_state.merge(hof_count: 0)
      curr = baseline_state.merge(hof_count: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 1, catch: 0 }, calls)
      end
    end

    test "all four pre-Step-17 event types fan out to all four coordinators exactly once each" do
      prev = baseline_state.merge(badges: 0,  trainer_id: 0,    secret_id: 0,
                                  pokedex_caught: 47, pokedex_seen: 89, hof_count: 0)
      curr = baseline_state.merge(badges: 1,  trainer_id: 1234, secret_id: 5678,
                                  pokedex_caught: 50, pokedex_seen: 92, hof_count: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 1, tid: 1, pokedex: 1, hof: 1, catch: 0 }, calls)
      end
    end

    # ── Step 17: catch + removal fan-out ──────────────────────────────────

    def party_h(pid)
      { pid: pid, species: 100, met_location_id: 16, level: 5,
        ot_id: 0, ot_sid: 0, is_egg: false }
    end

    test "PokemonCaughtEvent fans out to CatchCoordinator only" do
      prev = baseline_state.merge(party_data: [])
      curr = baseline_state.merge(party_data: [ party_h(0xAAAA) ])

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 1 }, calls)
      end
    end

    test "PokemonRemovedEvent also fans out to CatchCoordinator (single combined call)" do
      prev = baseline_state.merge(party_data: [ party_h(0xAAAA) ])
      curr = baseline_state.merge(party_data: [])

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 1 }, calls)
      end
    end

    test "stable PIDs across prev/curr produce no CatchCoordinator call" do
      stable = party_h(0xAAAA)
      prev = baseline_state.merge(party_data: [ stable ])
      curr = baseline_state.merge(party_data: [ stable ])

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    test "first-ever parse (prev[:parsed_at] nil) does not fan out catches even with party data" do
      # Baseline rule covers party_data the same as everything else —
      # importing a save with 6 mons doesn't produce 6 spurious catches.
      prev = baseline_state(parsed_at: nil).merge(party_data: nil)
      curr = baseline_state(parsed_at: Time.current).merge(
        party_data: [ party_h(0xAAAA), party_h(0xBBBB), party_h(0xCCCC) ]
      )

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    # ── Step 18: box diff fan-out ─────────────────────────────────────

    test "BoxedPokemonObservedEvent fans out to CatchCoordinator (single combined call)" do
      prev = baseline_state.merge(box_data: [])
      curr = baseline_state.merge(box_data: [ party_h(0xAAAA) ])

      captured_events = nil
      capture_stub = ->(_slot, events) { captured_events = events }
      noop = ->(*_args) { }

      SoulLink::GymBeatenCoordinator.stub(:process, noop) do
        SoulLink::TidObservationCoordinator.stub(:process, noop) do
          SoulLink::PokedexProgressCoordinator.stub(:process, noop) do
            SoulLink::HallOfFameCoordinator.stub(:process, noop) do
              SoulLink::CatchCoordinator.stub(:process, capture_stub) do
                SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
              end
            end
          end
        end
      end

      assert_not_nil captured_events
      assert_equal 1, captured_events.size
      assert_kind_of SoulLink::SaveDiff::BoxedPokemonObservedEvent, captured_events.first
    end

    test "stable box PIDs produce no CatchCoordinator call" do
      stable = party_h(0xAAAA)
      prev = baseline_state.merge(box_data: [ stable ])
      curr = baseline_state.merge(box_data: [ stable ])

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    test "first-ever parse does not fan out box events either (baseline rule)" do
      prev = baseline_state(parsed_at: nil).merge(box_data: nil)
      curr = baseline_state(parsed_at: Time.current).merge(
        box_data: [ party_h(0xAAAA), party_h(0xBBBB) ]
      )

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0, catch: 0 }, calls)
      end
    end

    test "Step 18: catch + box events arrive in a single combined CatchCoordinator call" do
      prev = baseline_state.merge(party_data: [], box_data: [])
      curr = baseline_state.merge(
        party_data: [ party_h(0xAAAA) ],
        box_data:   [ party_h(0xBBBB) ]
      )

      captured_events = nil
      capture_stub = ->(_slot, events) { captured_events = events }
      stub_coords = ->(*_args) { }

      SoulLink::GymBeatenCoordinator.stub(:process, stub_coords) do
        SoulLink::TidObservationCoordinator.stub(:process, stub_coords) do
          SoulLink::PokedexProgressCoordinator.stub(:process, stub_coords) do
            SoulLink::HallOfFameCoordinator.stub(:process, stub_coords) do
              SoulLink::CatchCoordinator.stub(:process, capture_stub) do
                SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
              end
            end
          end
        end
      end

      assert_not_nil captured_events
      assert_equal 2, captured_events.size
      # Order: catch_events first, then removal_events, then box_events.
      assert_kind_of SoulLink::SaveDiff::PokemonCaughtEvent,         captured_events[0]
      assert_kind_of SoulLink::SaveDiff::BoxedPokemonObservedEvent,  captured_events[1]
      assert_equal 0xAAAA, captured_events[0].pid
      assert_equal 0xBBBB, captured_events[1].pid
    end
  end
end
