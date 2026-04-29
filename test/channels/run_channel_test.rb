require "test_helper"

class RunChannelTest < ActionCable::Channel::TestCase
  include ActiveJob::TestHelper

  GREY = 153665622641737728
  GUILD_ID = 888888888888888888

  setup do
    @run = create(:soul_link_run, guild_id: GUILD_ID, active: true)
    stub_connection_with_session(current_user_id: GREY, guild_id: GUILD_ID)
  end

  # `ConnectionStub` from ActionCable's TestCase doesn't expose a session —
  # it only knows about `identified_by` attrs. The new guild authz check in
  # `RunChannel#subscribed` reads `connection.session[:guild_id]`, so the stub
  # has to fake one. Define the method on the stub's singleton class after
  # `stub_connection` builds it.
  def stub_connection_with_session(current_user_id:, guild_id:)
    stub_connection(current_user_id: current_user_id)
    fake_session = { guild_id: guild_id }
    connection.define_singleton_method(:session) { fake_session }
  end

  # ── subscription ────────────────────────────────────────────────────────

  test "subscribes and streams for guild" do
    subscribe(guild_id: GUILD_ID)

    assert subscription.confirmed?
    assert_has_stream RunChannel.broadcasting_for(GUILD_ID.to_s)
  end

  # ── #generate_emulator_roms ────────────────────────────────────────────

  test "generate_emulator_roms enqueues GenerateRunRomsJob and broadcasts state" do
    subscribe(guild_id: GUILD_ID)

    assert_enqueued_with(job: SoulLink::GenerateRunRomsJob, args: [ @run ]) do
      assert_broadcasts(RunChannel.broadcasting_for(GUILD_ID.to_s), 1) do
        perform :generate_emulator_roms
      end
    end
  end

  test "generate_emulator_roms is a no-op when sessions already exist" do
    4.times { create(:soul_link_emulator_session, :ready, soul_link_run: @run) }
    subscribe(guild_id: GUILD_ID)

    # Idempotent at the channel layer: don't enqueue, but still broadcast
    # so the client reconciles to current truth.
    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      assert_broadcasts(RunChannel.broadcasting_for(GUILD_ID.to_s), 1) do
        perform :generate_emulator_roms
      end
    end
  end

  test "generate_emulator_roms is a no-op when emulator_status is :generating" do
    create(:soul_link_emulator_session, :generating, soul_link_run: @run)
    subscribe(guild_id: GUILD_ID)

    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      perform :generate_emulator_roms
    end
  end

  test "generate_emulator_roms transmits error when no active run" do
    @run.deactivate!
    subscribe(guild_id: GUILD_ID)

    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      perform :generate_emulator_roms
    end

    assert_equal({ "error" => "No active run found" }, transmissions.last)
  end

  # ── #regenerate_emulator_roms ──────────────────────────────────────────
  #
  # Destructive retry. Only legal in the `:failed` state. Wipes all four
  # session rows (and their on-disk ROMs via the model's `after_destroy`),
  # then re-enqueues `GenerateRunRomsJob`. In any other state, no-op +
  # rebroadcast so the client reconciles to current truth.

  test "regenerate_emulator_roms destroys sessions and re-enqueues when status is :failed" do
    create(:soul_link_emulator_session, soul_link_run: @run, status: "failed", error_message: "boom")
    3.times { create(:soul_link_emulator_session, :ready, soul_link_run: @run) }
    assert_equal :failed, @run.reload.emulator_status

    subscribe(guild_id: GUILD_ID)

    assert_enqueued_with(job: SoulLink::GenerateRunRomsJob, args: [ @run ]) do
      assert_broadcasts(RunChannel.broadcasting_for(GUILD_ID.to_s), 1) do
        perform :regenerate_emulator_roms
      end
    end

    assert_equal 0, @run.reload.soul_link_emulator_sessions.count,
      "destroy_all should have removed every session row"
  end

  test "regenerate_emulator_roms is a no-op when emulator_status is :none" do
    subscribe(guild_id: GUILD_ID)
    assert_equal :none, @run.reload.emulator_status

    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      assert_broadcasts(RunChannel.broadcasting_for(GUILD_ID.to_s), 1) do
        perform :regenerate_emulator_roms
      end
    end
  end

  test "regenerate_emulator_roms is a no-op when emulator_status is :generating" do
    create(:soul_link_emulator_session, :generating, soul_link_run: @run)
    subscribe(guild_id: GUILD_ID)
    assert_equal :generating, @run.reload.emulator_status

    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      perform :regenerate_emulator_roms
    end
    # Sessions untouched — no-op must not destroy.
    assert_equal 1, @run.reload.soul_link_emulator_sessions.count
  end

  test "regenerate_emulator_roms is a no-op when emulator_status is :ready" do
    4.times { create(:soul_link_emulator_session, :ready, soul_link_run: @run) }
    subscribe(guild_id: GUILD_ID)
    assert_equal :ready, @run.reload.emulator_status

    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      perform :regenerate_emulator_roms
    end
    assert_equal 4, @run.reload.soul_link_emulator_sessions.count
  end

  test "regenerate_emulator_roms transmits error when no active run" do
    @run.deactivate!
    subscribe(guild_id: GUILD_ID)

    assert_no_enqueued_jobs(only: SoulLink::GenerateRunRomsJob) do
      perform :regenerate_emulator_roms
    end

    assert_equal({ "error" => "No active run found" }, transmissions.last)
  end

  # ── N+1 guard ──────────────────────────────────────────────────────────
  #
  # `broadcast_run_state` includes up to 20 past runs, each of which calls
  # `emulator_status` (which iterates `soul_link_emulator_sessions`). Without
  # eager-loading, that's 1 SELECT per past run + 1 for the current run.
  #
  # Past-run pokemon_group COUNTs are a separate, larger N+1 outside the
  # scope of this fix — we only assert on session queries.

  test "broadcast_run_state eager-loads sessions to avoid per-run N+1" do
    5.times do |i|
      past = create(:soul_link_run, guild_id: GUILD_ID, run_number: i + 10, active: false)
      create(:soul_link_emulator_session, :ready, soul_link_run: past)
    end
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      RunChannel.broadcast_run_state(GUILD_ID)
    end

    session_queries = queries.count { |q| q.include?("soul_link_emulator_sessions") }
    # Eager-load ⇒ 2 SELECTs total: one for current_run's sessions, one IN-clause
    # batch for all past_runs. Without `.includes`, this would be 6 (1 per run).
    assert_equal 2, session_queries,
      "N+1 detected on soul_link_emulator_sessions: #{session_queries} queries fired (expected 2 with eager-load)"
  end

  # The previous hard-pinned `assert_queries_count(16)` test was dropped in
  # favor of the targeted `session_queries == 2` regression above. A hard
  # total count flagged on every unrelated SELECT addition (e.g. counter
  # caches, schema lookups in CI) without protecting the load-bearing
  # invariant — N+1 on session preloads. The two-query assertion does that
  # job precisely.

  test "regenerate_emulator_roms cascades after_destroy and deletes rom files" do
    tmp_dir = Rails.root.join("tmp", "test_run_channel_regen")
    FileUtils.mkdir_p(tmp_dir)
    file = Tempfile.create(["rom", ".nds"], tmp_dir)
    file.close
    rel_path = Pathname.new(file.path).relative_path_from(Rails.root).to_s

    create(:soul_link_emulator_session, soul_link_run: @run, status: "failed",
                                        error_message: "boom", rom_path: rel_path)
    assert_equal :failed, @run.reload.emulator_status
    assert File.exist?(file.path), "precondition: rom tempfile must exist"

    subscribe(guild_id: GUILD_ID)
    perform :regenerate_emulator_roms

    assert_not File.exist?(file.path),
      "destroy_all should have cascaded after_destroy and removed the rom file"
  ensure
    File.delete(file.path) if file && File.exist?(file.path)
    FileUtils.rm_rf(tmp_dir) if tmp_dir
  end

  # ── guild authorization ────────────────────────────────────────────────
  #
  # The channel's `params[:guild_id]` is client-supplied and untrusted. It
  # must match the session's logged-in guild or the subscription is rejected.
  # Without this check, any authenticated user could stream another guild's
  # run state by passing a different guild_id in the subscribe params.

  test "subscribe is rejected when guild_id param does not match session guild" do
    other_guild = 777777777777777777
    subscribe(guild_id: other_guild)
    assert subscription.rejected?,
      "subscription with mismatched guild_id should be rejected"
  end

  test "subscribe is rejected when guild_id param is blank" do
    subscribe(guild_id: "")
    assert subscription.rejected?, "blank guild_id should be rejected"
  end

  test "subscribe is rejected when session has no guild_id" do
    # Wipe the stubbed session to simulate a connection without a logged-in
    # guild (shouldn't happen in production — Connection rejects unauth — but
    # belt-and-suspenders).
    connection.define_singleton_method(:session) { {} }
    subscribe(guild_id: GUILD_ID)
    assert subscription.rejected?, "missing session guild should be rejected"
  end

  # ── concurrent enqueue race ────────────────────────────────────────────
  #
  # Two parallel WS messages from the same client could race past the inner
  # `:none` check and double-enqueue. With `with_lock`, the second caller
  # blocks on the row's `SELECT … FOR UPDATE`, then re-reads `emulator_status`
  # (now != :none) and no-ops. We assert this by mocking `with_lock` directly:
  # a real thread test would need a true MySQL row lock and is brittle on
  # SQLite/in-memory. The mock-based assertion is what the brief calls a
  # "lighter test that asserts `with_lock` is called" — sufficient to lock
  # the contract.

  test "generate_emulator_roms wraps idempotency check in with_lock" do
    subscribe(guild_id: GUILD_ID)

    # Minitest's `stub` is per-instance and `SoulLinkRun.current` returns a
    # fresh AR object each call, so we can't stub via `@run`. Patch the
    # method on the class for the duration of the test instead.
    lock_called = false
    SoulLinkRun.class_eval do
      alias_method :__orig_with_lock, :with_lock
      define_method(:with_lock) do |&block|
        # Mark the call but skip the FOR UPDATE — SQLite/test DB doesn't
        # always support row-level locks anyway.
        Thread.current[:__lock_called] = true
        block.call
      end
    end

    begin
      Thread.current[:__lock_called] = false
      perform :generate_emulator_roms
      lock_called = Thread.current[:__lock_called]
    ensure
      SoulLinkRun.class_eval do
        alias_method :with_lock, :__orig_with_lock
        remove_method :__orig_with_lock
      end
      Thread.current[:__lock_called] = nil
    end

    assert lock_called, "expected with_lock to be invoked"
  end

  test "regenerate_emulator_roms wraps destroy+enqueue in with_lock" do
    create(:soul_link_emulator_session, soul_link_run: @run, status: "failed", error_message: "boom")
    subscribe(guild_id: GUILD_ID)

    SoulLinkRun.class_eval do
      alias_method :__orig_with_lock, :with_lock
      define_method(:with_lock) do |&block|
        Thread.current[:__lock_called] = true
        block.call
      end
    end

    begin
      Thread.current[:__lock_called] = false
      perform :regenerate_emulator_roms
      lock_called = Thread.current[:__lock_called]
    ensure
      SoulLinkRun.class_eval do
        alias_method :with_lock, :__orig_with_lock
        remove_method :__orig_with_lock
      end
      Thread.current[:__lock_called] = nil
    end

    assert lock_called, "expected with_lock to be invoked on regenerate"
  end

  # Behavioral check: under contention, only one job is enqueued. We simulate
  # the contention by manually flipping `emulator_status` mid-block (as a
  # real concurrent caller would, after acquiring the lock). The second
  # `generate_emulator_roms` call sees `:generating` under its own lock and
  # no-ops.
  test "two sequential generate_emulator_roms calls enqueue exactly one job (post-lock semantics)" do
    subscribe(guild_id: GUILD_ID)

    perform :generate_emulator_roms
    # First call enqueued — simulating job picking up and creating sessions.
    create(:soul_link_emulator_session, :generating, soul_link_run: @run)
    perform :generate_emulator_roms

    assert_equal 1, enqueued_jobs.count { |j| j[:job] == SoulLink::GenerateRunRomsJob },
      "second call should no-op now that emulator_status != :none"
  end
end
