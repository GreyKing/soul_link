require "test_helper"

class SoulLinkRunTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

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

  # ── avatar caching (Step 14) ───────────────────────────────────────────

  test "#avatar_for returns nil when no avatars are cached" do
    assert_nil @run.avatar_for(123)
  end

  test "#upsert_avatar! stores a new URL keyed by stringified user id" do
    @run.upsert_avatar!(123, "https://cdn.discord/abc.png")
    assert_equal "https://cdn.discord/abc.png", @run.reload.avatar_for(123)
    assert_equal "https://cdn.discord/abc.png", @run.player_avatars["123"]
  end

  test "#upsert_avatar! updates an existing URL" do
    @run.upsert_avatar!(123, "https://cdn.discord/old.png")
    @run.upsert_avatar!(123, "https://cdn.discord/new.png")
    assert_equal "https://cdn.discord/new.png", @run.reload.avatar_for(123)
  end

  test "#upsert_avatar! is a no-op when URL is unchanged" do
    @run.upsert_avatar!(123, "https://cdn.discord/abc.png")
    before = @run.reload.updated_at
    travel 1.second do
      @run.upsert_avatar!(123, "https://cdn.discord/abc.png")
    end
    assert_equal before, @run.reload.updated_at
  end

  test "#upsert_avatar! with a blank URL deletes any existing entry" do
    @run.upsert_avatar!(123, "https://cdn.discord/abc.png")
    @run.upsert_avatar!(123, nil)
    assert_nil @run.reload.avatar_for(123)
  end

  test "#upsert_avatar! returns silently for a blank user id" do
    @run.upsert_avatar!(nil, "https://cdn.discord/abc.png")
    assert_nil @run.player_avatars
  end

  # ── Step 16: completion ────────────────────────────────────────────────

  test "#completed? is true when completed_at is set, false otherwise" do
    assert_not @run.completed?
    @run.update!(completed_at: Time.current)
    assert @run.completed?
  end

  # ── Step 19: wiped + read_only ─────────────────────────────────────────

  test "#wiped? is true when wiped_at is set, false otherwise" do
    assert_not @run.wiped?
    @run.update!(wiped_at: Time.current)
    assert @run.wiped?
  end

  test "#read_only? is true when wiped and NOT completed" do
    @run.update!(wiped_at: Time.current)
    assert @run.read_only?
  end

  test "#read_only? is false when only completed (HoF wins)" do
    @run.update!(completed_at: Time.current)
    assert_not @run.read_only?
  end

  test "#read_only? is false when both wiped and completed (HoF wins)" do
    @run.update!(wiped_at: Time.current, completed_at: Time.current)
    assert_not @run.read_only?
  end

  test "#read_only? is false when neither wiped nor completed" do
    assert_not @run.read_only?
  end

  test "#broadcast_state includes wiped_at as ISO8601 (or nil)" do
    payload = @run.broadcast_state
    assert_includes payload.keys, :wiped_at
    assert_nil payload[:wiped_at]

    t = Time.current
    @run.update!(wiped_at: t)
    assert_equal t.iso8601, @run.broadcast_state[:wiped_at]
  end

  # ── Step 16: TID conflict detection ────────────────────────────────────

  test "#tid_conflict_groups is empty when no sessions exist" do
    assert_equal [], @run.tid_conflict_groups
  end

  test "#tid_conflict_groups is empty when all sessions have unique TIDs" do
    sess = 4.times.map do |i|
      create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 700 + i)
    end
    sess.each_with_index do |s, i|
      create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1,
             parsed_trainer_id: 1000 + i, parsed_secret_id: 2000 + i)
    end

    assert_equal [], @run.reload.tid_conflict_groups
  end

  test "#tid_conflict_groups returns one group of two ids when two sessions share (TID, SID)" do
    sess = 4.times.map do |i|
      create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 800 + i)
    end
    # Sessions 0 and 2 share the same (TID, SID).
    [
      [ 1234, 5678 ],
      [ 9999, 1111 ],
      [ 1234, 5678 ],
      [ 7777, 8888 ]
    ].each_with_index do |(tid, sid), i|
      create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess[i], slot_number: 1,
             parsed_trainer_id: tid, parsed_secret_id: sid)
    end

    groups = @run.reload.tid_conflict_groups
    assert_equal 1, groups.size
    assert_equal [ sess[0].id, sess[2].id ].sort, groups.first.sort
  end

  test "#tid_conflict_groups returns one group of four ids when all 4 sessions share (TID, SID)" do
    sess = 4.times.map do |i|
      create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 900 + i)
    end
    sess.each do |s|
      create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1,
             parsed_trainer_id: 1234, parsed_secret_id: 5678)
    end

    groups = @run.reload.tid_conflict_groups
    assert_equal 1, groups.size
    assert_equal sess.map(&:id).sort, groups.first.sort
  end

  test "#tid_conflict_groups ignores sessions with nil/zero TID (unparsed slots)" do
    sess = 4.times.map do |i|
      create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 1000 + i)
    end
    # Two slots have TID 0 (unparsed); two share a real (TID, SID).
    [
      [ 0, 0 ],
      [ 1234, 5678 ],
      [ 0, 0 ],
      [ 1234, 5678 ]
    ].each_with_index do |(tid, sid), i|
      create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess[i], slot_number: 1,
             parsed_trainer_id: tid, parsed_secret_id: sid)
    end

    groups = @run.reload.tid_conflict_groups
    assert_equal 1, groups.size, "the two TID=0 slots must NOT be flagged as a conflict group"
    assert_equal [ sess[1].id, sess[3].id ].sort, groups.first.sort
  end

  test "#tid_conflict_groups distinguishes (TID, SID) pairs (same TID, different SID is not a conflict)" do
    sess = 2.times.map do |i|
      create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 1100 + i)
    end
    # Same TID, different SID — NOT a conflict (different save).
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess[0], slot_number: 1,
           parsed_trainer_id: 1234, parsed_secret_id: 5678)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess[1], slot_number: 1,
           parsed_trainer_id: 1234, parsed_secret_id: 9999)

    assert_equal [], @run.reload.tid_conflict_groups
  end
end
