require "test_helper"

module SoulLink
  class PokedexProgressCoordinatorTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      @session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
      @slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    end

    def event(caught_delta:, seen_delta:, curr_caught:, curr_seen:)
      SoulLink::SaveDiff::PokedexProgress.new(
        caught_delta: caught_delta, seen_delta: seen_delta,
        curr_caught: curr_caught, curr_seen: curr_seen
      )
    end

    test "process is a no-op when events is empty" do
      assert_nothing_raised do
        SoulLink::PokedexProgressCoordinator.process(@slot, [])
      end
    end

    test "process logs at info level for each PokedexProgress event" do
      events = [ event(caught_delta: 5, seen_delta: 3, curr_caught: 52, curr_seen: 92) ]

      log = capture_log do
        SoulLink::PokedexProgressCoordinator.process(@slot, events)
      end

      assert_match(/caught Δ5 \(now 52\)/, log)
      assert_match(/seen Δ3 \(now 92\)/, log)
      assert_match(/run=#{@run.id}/, log)
    end

    test "process is a no-op when the slot has no run (orphan)" do
      orphan_slot = build(:soul_link_emulator_save_slot)
      orphan_slot.define_singleton_method(:soul_link_emulator_session) { nil }

      assert_nothing_raised do
        SoulLink::PokedexProgressCoordinator.process(
          orphan_slot,
          [ event(caught_delta: 1, seen_delta: 1, curr_caught: 1, curr_seen: 1) ]
        )
      end
    end

    test "process produces no AR side effects (no row counts change)" do
      events = [ event(caught_delta: 5, seen_delta: 3, curr_caught: 52, curr_seen: 92) ]

      assert_no_difference [
        "SoulLinkRun.count",
        "SoulLinkEmulatorSession.count",
        "SoulLinkEmulatorSaveSlot.count",
        "GymResult.count"
      ] do
        SoulLink::PokedexProgressCoordinator.process(@slot, events)
      end
    end

    private

    def capture_log
      original = Rails.logger
      io = StringIO.new
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
      io.string
    ensure
      Rails.logger = original
    end
  end
end
