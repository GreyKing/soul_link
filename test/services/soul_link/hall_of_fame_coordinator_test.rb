require "test_helper"

module SoulLink
  class HallOfFameCoordinatorTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::TimeHelpers

    setup do
      @run = create(:soul_link_run)
      # Four ready sessions with one active slot each. Mirrors the
      # GymBeatenCoordinatorTest harness so the all-4 AND-gate is
      # exercised the same way.
      @sessions = 4.times.map do |i|
        create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 100 + i)
      end
      @slots = @sessions.map do |s|
        create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1, parsed_hof_count: 0, parsed_at: 1.minute.ago)
      end
    end

    def event(hof_count = 1)
      SoulLink::SaveDiff::HallOfFameEntered.new(hof_count: hof_count)
    end

    # ── 4/4 → completed_at set ────────────────────────────────────────────

    test "4/4 sessions with parsed_hof_count >= 1 → run.completed_at set" do
      @slots.each { |slot| slot.update_columns(parsed_hof_count: 1) }
      assert_nil @run.completed_at

      freeze_time do
        SoulLink::HallOfFameCoordinator.process(@slots.first, [ event ])
        assert_equal Time.current, @run.reload.completed_at
      end
    end

    # ── 3/4 → no-op ───────────────────────────────────────────────────────

    test "3/4 sessions with parsed_hof_count >= 1 → completed_at stays nil" do
      @slots[0..2].each { |slot| slot.update_columns(parsed_hof_count: 1) }

      SoulLink::HallOfFameCoordinator.process(@slots.first, [ event ])
      assert_nil @run.reload.completed_at
    end

    # ── idempotency ───────────────────────────────────────────────────────

    test "run already completed (completed_at set) → no-op (does not bump completed_at)" do
      @slots.each { |slot| slot.update_columns(parsed_hof_count: 1) }
      original_completion = 2.days.ago.beginning_of_minute
      @run.update_columns(completed_at: original_completion)

      SoulLink::HallOfFameCoordinator.process(@slots.first, [ event ])
      assert_equal original_completion.to_i, @run.reload.completed_at.to_i
    end

    # ── inactive run ──────────────────────────────────────────────────────

    test "run inactive → no-op even when 4/4 satisfy" do
      @slots.each { |slot| slot.update_columns(parsed_hof_count: 1) }
      @run.update_columns(active: false)

      SoulLink::HallOfFameCoordinator.process(@slots.first, [ event ])
      assert_nil @run.reload.completed_at
    end

    # ── empty session set ─────────────────────────────────────────────────

    test "0 sessions → all_players_in_hall_of_fame? returns false (don't false-positive empty run)" do
      lone_run = create(:soul_link_run, guild_id: 222222222222222222)
      assert_not SoulLink::HallOfFameCoordinator.all_players_in_hall_of_fame?(lone_run)
    end

    # ── session with no active slot ───────────────────────────────────────

    test "session with no active slot → all_players_in_hall_of_fame? returns false" do
      @slots[0..2].each { |slot| slot.update_columns(parsed_hof_count: 1) }
      @sessions[3].update_columns(active_save_slot: nil)

      assert_not SoulLink::HallOfFameCoordinator.all_players_in_hall_of_fame?(@run.reload)
    end

    # ── empty event array ─────────────────────────────────────────────────

    test "process with empty events is a no-op (does not even read the run)" do
      @slots.each { |slot| slot.update_columns(parsed_hof_count: 1) }

      assert_nothing_raised do
        SoulLink::HallOfFameCoordinator.process(@slots.first, [])
      end
      assert_nil @run.reload.completed_at
    end
  end
end
