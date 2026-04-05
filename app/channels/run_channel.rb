class RunChannel < ApplicationCable::Channel
  def subscribed
    @guild_id = params[:guild_id]
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

  def self.broadcast_run_state(guild_id)
    current_run = SoulLinkRun.current(guild_id)
    past_runs = SoulLinkRun.history(guild_id).limit(20)

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
    current_run = SoulLinkRun.current(@guild_id)
    past_runs = SoulLinkRun.history(@guild_id).limit(20)

    {
      type: "state_update",
      state: {
        current_run: current_run&.broadcast_state,
        past_runs: past_runs.map(&:broadcast_state)
      }
    }
  end
end
