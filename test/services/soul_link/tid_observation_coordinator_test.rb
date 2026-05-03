require "test_helper"

module SoulLink
  class TidObservationCoordinatorTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      @session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
      @slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    end

    def event(tid, sid)
      SoulLink::SaveDiff::TidObserved.new(trainer_id: tid, secret_id: sid)
    end

    test "process is a no-op when events is empty" do
      assert_nothing_raised do
        SoulLink::TidObservationCoordinator.process(@slot, [])
      end
    end

    test "process logs at info level for each TidObserved event" do
      events = [ event(1234, 5678), event(9999, 1111) ]

      log = capture_log do
        SoulLink::TidObservationCoordinator.process(@slot, events)
      end

      assert_match(/TID=1234 SID=5678/, log)
      assert_match(/TID=9999 SID=1111/, log)
      assert_match(/run=#{@run.id}/, log)
    end

    test "process is a no-op when the slot has no run (orphan)" do
      orphan_slot = build(:soul_link_emulator_save_slot)
      orphan_slot.define_singleton_method(:soul_link_emulator_session) { nil }

      assert_nothing_raised do
        SoulLink::TidObservationCoordinator.process(orphan_slot, [ event(1234, 5678) ])
      end
    end

    test "process produces no AR side effects (no row counts change)" do
      events = [ event(1234, 5678) ]

      assert_no_difference [
        "SoulLinkRun.count",
        "SoulLinkEmulatorSession.count",
        "SoulLinkEmulatorSaveSlot.count",
        "GymResult.count"
      ] do
        SoulLink::TidObservationCoordinator.process(@slot, events)
      end
    end

    private

    # Capture the Rails.logger output produced inside the block. Returns
    # the captured String. Restores the original logger afterwards.
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
