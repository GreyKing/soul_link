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

  # ── one-active-run-per-guild invariant (Step 11) ─────────────────────────
  #
  # Enforced at two layers:
  #   1. Model `validate :no_other_active_run_for_guild` — friendly error
  #      so callers see `record.errors` instead of a 500.
  #   2. DB-level virtual-column unique index on `active_guild_id` — last
  #      line of defense. Catches races, raw SQL, manual tampering.

  test "validates only one active run per guild" do
    duplicate = build(:soul_link_run, guild_id: @run.guild_id, run_number: @run.run_number + 1)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:active], "another run is already active for this guild"
  end

  test "allows a second run for the same guild after deactivating the first" do
    @run.deactivate!

    next_run = build(:soul_link_run, guild_id: @run.guild_id, run_number: @run.run_number + 1)

    assert next_run.valid?
  end

  test "allows runs in different guilds to be simultaneously active" do
    other = build(:soul_link_run, guild_id: @run.guild_id + 1, run_number: 1)

    assert other.valid?
  end

  test "allows updating an already-active run without self-conflict" do
    @run.update!(gyms_defeated: 3)

    assert_equal 3, @run.reload.gyms_defeated
  end

  test "DB-level unique index catches a race that bypassed the model validation" do
    # Simulate a TOCTOU race: a second active row tries to slip in via raw
    # SQL, bypassing AR validations entirely. The DB constraint must
    # catch it. `INSERT IGNORE`/`upsert` paths or rogue scripts would hit
    # the same path.
    assert_raises(ActiveRecord::RecordNotUnique) do
      SoulLinkRun.connection.execute(<<~SQL.squish)
        INSERT INTO soul_link_runs
          (guild_id, run_number, active, gyms_defeated, created_at, updated_at)
        VALUES
          (#{@run.guild_id}, #{@run.run_number + 1}, 1, 0, NOW(), NOW())
      SQL
    end
  end

  # ── .current(guild_id) ──────────────────────────────────────────────────

  test ".current returns the single active run for a guild" do
    assert_equal @run, SoulLinkRun.current(@run.guild_id)
  end

  test ".current returns nil when no active run exists for guild" do
    @run.deactivate!

    assert_nil SoulLinkRun.current(@run.guild_id)
  end

  test ".current returns nil for an unknown guild" do
    assert_nil SoulLinkRun.current(@run.guild_id + 999)
  end
end
