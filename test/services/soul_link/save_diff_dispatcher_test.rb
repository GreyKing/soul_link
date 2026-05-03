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
        hof_count:      0
      }
    end

    # Stub all four coordinators with a no-op closure that records each
    # call. Yields the +calls+ Hash so the test body can inspect it.
    def with_stubbed_coordinators
      calls = { gym: 0, tid: 0, pokedex: 0, hof: 0 }
      gym  = ->(*_args) { calls[:gym]     += 1 }
      tid  = ->(*_args) { calls[:tid]     += 1 }
      dex  = ->(*_args) { calls[:pokedex] += 1 }
      hof  = ->(*_args) { calls[:hof]     += 1 }
      SoulLink::GymBeatenCoordinator.stub(:process, gym) do
        SoulLink::TidObservationCoordinator.stub(:process, tid) do
          SoulLink::PokedexProgressCoordinator.stub(:process, dex) do
            SoulLink::HallOfFameCoordinator.stub(:process, hof) do
              yield calls
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
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0 }, calls)
      end
    end

    test "empty diff (every value equal) does not call any coordinator" do
      prev = baseline_state.merge(badges: 3, trainer_id: 1234, secret_id: 5678,
                                  pokedex_caught: 47, pokedex_seen: 89, hof_count: 0)
      curr = baseline_state.merge(badges: 3, trainer_id: 1234, secret_id: 5678,
                                  pokedex_caught: 47, pokedex_seen: 89, hof_count: 0)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 0 }, calls)
      end
    end

    # ── per-category dispatch ─────────────────────────────────────────────

    test "BadgeGained event only invokes GymBeatenCoordinator" do
      prev = baseline_state.merge(badges: 0)
      curr = baseline_state.merge(badges: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 1, tid: 0, pokedex: 0, hof: 0 }, calls)
      end
    end

    test "TidObserved event only invokes TidObservationCoordinator" do
      prev = baseline_state.merge(trainer_id: 0, secret_id: 0)
      curr = baseline_state.merge(trainer_id: 1234, secret_id: 5678)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 1, pokedex: 0, hof: 0 }, calls)
      end
    end

    test "PokedexProgress event only invokes PokedexProgressCoordinator" do
      prev = baseline_state.merge(pokedex_caught: 47, pokedex_seen: 89)
      curr = baseline_state.merge(pokedex_caught: 50, pokedex_seen: 92)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 1, hof: 0 }, calls)
      end
    end

    test "HallOfFameEntered event only invokes HallOfFameCoordinator" do
      prev = baseline_state.merge(hof_count: 0)
      curr = baseline_state.merge(hof_count: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 0, tid: 0, pokedex: 0, hof: 1 }, calls)
      end
    end

    test "all four event types fan out to all four coordinators exactly once each" do
      prev = baseline_state.merge(badges: 0,  trainer_id: 0,    secret_id: 0,
                                  pokedex_caught: 47, pokedex_seen: 89, hof_count: 0)
      curr = baseline_state.merge(badges: 1,  trainer_id: 1234, secret_id: 5678,
                                  pokedex_caught: 50, pokedex_seen: 92, hof_count: 1)

      with_stubbed_coordinators do |calls|
        SoulLink::SaveDiffDispatcher.dispatch(@slot, prev: prev, curr: curr)
        assert_equal({ gym: 1, tid: 1, pokedex: 1, hof: 1 }, calls)
      end
    end
  end
end
