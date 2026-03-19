class GymScheduleChannel < ApplicationCable::Channel
  def subscribed
    @schedule = GymSchedule.find(params[:schedule_id])
    stream_for @schedule
    broadcast_state
  end

  def unsubscribed
    # No cleanup needed
  end

  def rsvp(data)
    @schedule.reload
    @schedule.rsvp!(current_user_id, data["response"])
    broadcast_state
    GymScheduleDiscordUpdateJob.perform_later(@schedule.id) if @schedule.discord_message_id
  rescue => e
    transmit(error: e.message)
  end

  def cancel(_data)
    @schedule.reload
    @schedule.cancel!
    broadcast_state
  rescue => e
    transmit(error: e.message)
  end

  private

  def broadcast_state
    @schedule.reload
    GymScheduleChannel.broadcast_to(@schedule, { type: "state_update", state: @schedule.broadcast_state })
  end
end
