class GymPollChannel < ApplicationCable::Channel
  def subscribed
    @poll = GymPoll.find(params[:id])
    stream_for @poll
    broadcast_state
  end

  def vote(data)
    unless SoulLink::GameState.registered_player?(current_user_id)
      transmit(type: "error", message: "You aren't a player in this run.")
      return
    end

    @poll.reload
    @poll.vote!(current_user_id, data["slot_index"].to_i, data["response"])
    broadcast_state
  rescue => e
    transmit(type: "error", message: e.message)
  end

  def reset(_data = {})
    @poll.reload
    GymPollChannel.broadcast_to(@poll, type: "poll_reset")
    @poll.destroy
  rescue => e
    transmit(type: "error", message: e.message)
  end

  private

  def broadcast_state
    GymPollChannel.broadcast_to(@poll, type: "state_update", state: @poll.broadcast_state)
  end
end
