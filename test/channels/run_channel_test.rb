require "test_helper"

class RunChannelTest < ActionCable::Channel::TestCase
  include ActiveJob::TestHelper

  GREY = 153665622641737728
  GUILD_ID = 888888888888888888

  setup do
    @run = create(:soul_link_run, guild_id: GUILD_ID, active: true)
    stub_connection(current_user_id: GREY)
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
end
