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
end
