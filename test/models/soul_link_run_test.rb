require "test_helper"

class SoulLinkRunTest < ActiveSupport::TestCase
  setup do
    @run = create(:soul_link_run)
  end

  # ── #emulator_status ────────────────────────────────────────────────────

  test "#emulator_status returns :none when no sessions exist" do
    assert_equal :none, @run.emulator_status
  end

  test "#emulator_status returns :ready when all 4 sessions are ready" do
    4.times { create(:soul_link_emulator_session, :ready, soul_link_run: @run) }

    assert_equal :ready, @run.reload.emulator_status
  end

  test "#emulator_status returns :generating when any session is pending or generating" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :generating, soul_link_run: @run)

    assert_equal :generating, @run.reload.emulator_status
  end

  test "#emulator_status returns :generating when a session is pending (default factory state)" do
    create(:soul_link_emulator_session, soul_link_run: @run) # pending by default
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    assert_equal :generating, @run.reload.emulator_status
  end

  test "#emulator_status returns :failed when any session has failed" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, soul_link_run: @run, status: "failed")

    assert_equal :failed, @run.reload.emulator_status
  end

  test "#emulator_status prioritizes :failed over :generating" do
    # One failed + one still generating — failed should win so the user
    # sees the problem rather than waiting on a stuck-generating indicator.
    create(:soul_link_emulator_session, soul_link_run: @run, status: "failed")
    create(:soul_link_emulator_session, :generating, soul_link_run: @run)

    assert_equal :failed, @run.reload.emulator_status
  end

  # ── #broadcast_state ────────────────────────────────────────────────────

  test "#broadcast_state includes emulator_status key" do
    payload = @run.broadcast_state

    assert_includes payload.keys, :emulator_status
    assert_equal :none, payload[:emulator_status]
  end

  test "#broadcast_state reflects current emulator_status" do
    4.times { create(:soul_link_emulator_session, :ready, soul_link_run: @run) }

    assert_equal :ready, @run.reload.broadcast_state[:emulator_status]
  end
end
