class GymDraftChannel < ApplicationCable::Channel
  def subscribed
    @draft = GymDraft.find(params[:draft_id])
    stream_for @draft
    broadcast_state
  end

  def unsubscribed
    # No cleanup needed
  end

  def ready(_data)
    @draft.reload
    @draft.mark_ready!(current_user_id)
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def vote(data)
    @draft.reload
    @draft.cast_vote!(current_user_id, data["voted_for"])
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def pick(data)
    @draft.reload
    @draft.make_pick!(current_user_id, data["group_id"])
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def nominate(data)
    @draft.reload
    @draft.submit_nomination!(current_user_id, data["group_id"])
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def vote_nomination(data)
    @draft.reload
    @draft.vote_on_nomination!(current_user_id, data["approve"])
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  private

  def broadcast_state
    @draft.reload
    GymDraftChannel.broadcast_to(@draft, { type: "state_update", state: @draft.broadcast_state })
  end
end
