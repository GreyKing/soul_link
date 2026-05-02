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

  # Step 14 unified action: model auto-detects "new candidate" vs.
  # "endorsement" based on whether the group_id is already on the
  # candidates list. The legacy `vote_nomination` action is gone.
  def nominate(data)
    @draft.reload
    @draft.nominate!(current_user_id, data["group_id"])
    broadcast_state
  rescue => e
    transmit({ error: e.message })
  end

  def skip(_data)
    @draft.reload
    @draft.skip_turn!(current_user_id)
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
