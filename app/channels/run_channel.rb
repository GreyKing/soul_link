class RunChannel < ApplicationCable::Channel
  def subscribed
    guild_id = params[:guild_id]
    # Authorize the subscription against the session's logged-in guild. The
    # client-supplied `guild_id` param is untrusted — without this check, any
    # authenticated user could stream another guild's run state by simply
    # passing a different param. Compare as strings since `params` may carry
    # the value as a String while the session value is an Integer (cast by
    # SessionsController#create at login time).
    session_guild_id = connection.session && connection.session[:guild_id]
    if guild_id.blank? || session_guild_id.blank? || guild_id.to_s != session_guild_id.to_s
      reject
      return
    end
    @guild_id = guild_id
    stream_for @guild_id
    transmit build_state_payload
  end

  def unsubscribed
    # No cleanup needed
  end

  def start_run(_data)
    # Deactivate current run if exists
    SoulLinkRun.current(@guild_id)&.deactivate!

    # Determine next run number
    last_run = SoulLinkRun.for_guild(@guild_id).order(run_number: :desc).first
    next_number = last_run ? last_run.run_number + 1 : 1

    SoulLinkRun.create!(
      guild_id: @guild_id,
      run_number: next_number
    )

    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def end_run(_data)
    run = SoulLinkRun.current(@guild_id)
    unless run
      transmit({ error: "No active run found" })
      return
    end

    run.deactivate!
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def setup_discord(_data)
    run = SoulLinkRun.current(@guild_id)
    unless run
      transmit({ error: "No active run found" })
      return
    end

    if run.discord_channels_configured?
      transmit({ error: "Discord channels already configured" })
      return
    end

    SoulLink::DiscordApi.new.create_run_channels(@guild_id, run)
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def generate_emulator_roms(_data)
    run = SoulLinkRun.current(@guild_id)
    unless run
      transmit({ error: "No active run found" })
      return
    end

    # Idempotency under contention: two parallel WS messages from the same or
    # different clients can race past the `:none` check and double-enqueue.
    # `with_lock` opens a transaction with `SELECT … FOR UPDATE` on the run
    # row; the second caller blocks until the first commits, then re-reads
    # `emulator_status` (now != :none) and no-ops. Cheaper than an advisory
    # lock and self-healing if the connection drops mid-block.
    run.with_lock do
      if run.emulator_status == :none
        SoulLink::GenerateRunRomsJob.perform_later(run)
      end
    end

    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def regenerate_emulator_roms(_data)
    run = SoulLinkRun.current(@guild_id)
    unless run
      transmit({ error: "No active run found" })
      return
    end

    # Same locking rationale as `generate_emulator_roms`. The destroy_all
    # cascade and subsequent re-enqueue must happen atomically per run row,
    # so concurrent regenerate clicks cannot fire the destroy twice or
    # interleave a destroy with a half-finished regenerate.
    #
    # `destroy_all` (NOT `delete_all`) so the `after_destroy` callback fires
    # for each session and the on-disk ROM files get cleaned up. This wipes
    # save_data along with the rows.
    run.with_lock do
      if run.emulator_status == :failed
        run.soul_link_emulator_sessions.destroy_all
        SoulLink::GenerateRunRomsJob.perform_later(run)
      end
    end

    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def self.broadcast_run_state(guild_id)
    # Eager-load `soul_link_emulator_sessions` so each run's `emulator_status`
    # check (called inside `broadcast_state`) reuses the loaded collection
    # instead of issuing a SELECT per row.
    current_run = SoulLinkRun.active.for_guild(guild_id)
                              .includes(:soul_link_emulator_sessions)
                              .order(run_number: :desc).first
    past_runs = SoulLinkRun.history(guild_id)
                            .includes(:soul_link_emulator_sessions)
                            .limit(20)

    payload = {
      type: "state_update",
      state: {
        current_run: current_run&.broadcast_state,
        past_runs: past_runs.map(&:broadcast_state)
      }
    }

    broadcast_to(guild_id, payload)
  end

  private

  def broadcast_state
    RunChannel.broadcast_run_state(@guild_id)
  end

  def build_state_payload
    # Mirror the eager-load in `broadcast_run_state` — same N+1 risk applies
    # on initial subscribe.
    current_run = SoulLinkRun.active.for_guild(@guild_id)
                              .includes(:soul_link_emulator_sessions)
                              .order(run_number: :desc).first
    past_runs = SoulLinkRun.history(@guild_id)
                            .includes(:soul_link_emulator_sessions)
                            .limit(20)

    {
      type: "state_update",
      state: {
        current_run: current_run&.broadcast_state,
        past_runs: past_runs.map(&:broadcast_state)
      }
    }
  end
end
