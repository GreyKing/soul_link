class CleanupCurrentNominationFromInflightDrafts < ActiveRecord::Migration[8.1]
  # Step 14 rewires the nominating phase from a round-robin "submit then
  # vote" loop into a single 4-pick "nominate or endorse" pass. The old
  # `current_nomination` JSON sub-key is dropped entirely. Any draft
  # currently parked in `nominating` under the old code carries that key
  # and would crash on the new model methods. We strip it once and seed
  # the new shape so the migration is safe to run on production.
  #
  # Idempotent: the `next unless data.key?("current_nomination")` guard
  # makes a second run a no-op.
  def up
    GymDraft.where(status: "nominating").find_each do |draft|
      data = draft.state_data || {}
      next unless data.key?("current_nomination")
      data.delete("current_nomination")
      data["candidates"] ||= []
      data["current_turn_started_at"] = Time.current.iso8601
      draft.update_columns(state_data: data)
    end
  end

  def down
    # No-op; data is gone.
  end
end
