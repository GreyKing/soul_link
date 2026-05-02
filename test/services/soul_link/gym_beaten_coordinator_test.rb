require "test_helper"

module SoulLink
  class GymBeatenCoordinatorTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      # Four ready sessions with one active slot each. The slot is
      # the per-session "currently active save slot" the coordinator
      # consults via `session.active_slot`.
      @sessions = 4.times.map do |i|
        create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 100 + i)
      end
      @slots = @sessions.map do |s|
        create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1, parsed_badges: 0, parsed_at: 1.minute.ago)
      end
    end

    def event(klass, gym_number)
      klass.new(gym_number: gym_number)
    end

    # --- BadgeGained → all-4 satisfied -------------------------------------

    test "BadgeGained with 4/4 players, no suppression, no existing → creates gym_results and bumps gyms_defeated" do
      @slots.each { |slot| slot.update_columns(parsed_badges: 4) }

      assert_difference "@run.gym_results.count", 1 do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end

      assert @run.gym_results.exists?(gym_number: 4)
      assert_equal 4, @run.reload.gyms_defeated
    end

    test "BadgeGained with 3/4 players → no gym_results created" do
      # First three slots have the badge; fourth doesn't.
      @slots[0..2].each { |slot| slot.update_columns(parsed_badges: 4) }

      assert_no_difference "@run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end
      assert_equal 0, @run.reload.gyms_defeated
    end

    # --- idempotency / suppression ------------------------------------------

    test "BadgeGained when gym_results already exists → no-op" do
      @slots.each { |slot| slot.update_columns(parsed_badges: 4) }
      @run.gym_results.create!(gym_number: 4, beaten_at: Time.current)

      assert_no_difference "@run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end
    end

    test "BadgeGained when suppression exists → no-op" do
      @slots.each { |slot| slot.update_columns(parsed_badges: 4) }
      create(:gym_auto_mark_suppression, soul_link_run: @run, gym_number: 4)

      assert_no_difference "@run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end
    end

    # --- BadgeLost ---------------------------------------------------------

    test "BadgeLost is a no-op (no destroy, no create)" do
      @run.gym_results.create!(gym_number: 4, beaten_at: Time.current)

      assert_no_difference "@run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeLost, 4) ])
      end
    end

    # --- defensive guards ---------------------------------------------------

    test "inactive run → no-op" do
      @run.update_columns(active: false)
      @slots.each { |slot| slot.update_columns(parsed_badges: 4) }

      assert_no_difference "@run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(@slots.first, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end
    end

    test "0 sessions → all_players_have_badge? returns false (no auto-mark)" do
      lone_run = create(:soul_link_run, guild_id: 222222222222222222)
      lone_slot = build(:soul_link_emulator_save_slot)
      # Stub the slot's session/run chain so process can resolve a run with zero sessions.
      lone_session_double = Object.new
      lone_session_double.define_singleton_method(:soul_link_run) { lone_run }
      lone_slot.define_singleton_method(:soul_link_emulator_session) { lone_session_double }

      assert_not SoulLink::GymBeatenCoordinator.all_players_have_badge?(lone_run, 4)

      assert_no_difference "lone_run.gym_results.count" do
        SoulLink::GymBeatenCoordinator.process(lone_slot, [ event(SoulLink::SaveDiff::BadgeGained, 4) ])
      end
    end

    test "session with no active_slot → all_players_have_badge? returns false" do
      # Player 4 has no active_slot set (e.g. ROM generated but no save uploaded yet).
      @slots[0..2].each { |slot| slot.update_columns(parsed_badges: 4) }
      @sessions[3].update_columns(active_save_slot: nil)

      assert_not SoulLink::GymBeatenCoordinator.all_players_have_badge?(@run.reload, 4)
    end

    # --- transactional create + counter bump --------------------------------

    test "attempt_auto_mark wraps create + counter bump in a transaction" do
      @slots.each { |slot| slot.update_columns(parsed_badges: 4) }

      # Stub the run's update! to raise a non-Rollback exception. Critical:
      # ActiveRecord::Rollback is silently swallowed by `transaction { }`,
      # so a Rollback-based stub would pass even if the implementation
      # never wrapped the writes in a transaction at all (the create!
      # would succeed and the count would change). Raising a RuntimeError
      # forces the transaction to actually propagate while still rolling
      # back the create — the only way the count assertion holds is if
      # the implementation correctly wraps create! + update! in
      # `run.transaction do ... end`.
      run_proxy = SoulLinkRun.find(@run.id)
      run_proxy.define_singleton_method(:update!) { |*| raise RuntimeError, "stub" }

      assert_no_difference "@run.gym_results.count" do
        assert_raises(RuntimeError) do
          SoulLink::GymBeatenCoordinator.attempt_auto_mark(run_proxy, 4)
        end
      end
    end

    # --- multi-event sequence -----------------------------------------------

    test "multi-event sequence (gym 1 then gym 2) creates two gym_results when all-4 satisfy" do
      @slots.each { |slot| slot.update_columns(parsed_badges: 2) }

      events = [
        event(SoulLink::SaveDiff::BadgeGained, 1),
        event(SoulLink::SaveDiff::BadgeGained, 2)
      ]

      assert_difference "@run.gym_results.count", 2 do
        SoulLink::GymBeatenCoordinator.process(@slots.first, events)
      end

      assert @run.gym_results.exists?(gym_number: 1)
      assert @run.gym_results.exists?(gym_number: 2)
      assert_equal 2, @run.reload.gyms_defeated
    end
  end
end
