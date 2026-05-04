class AddWipedAtToSoulLinkRuns < ActiveRecord::Migration[8.1]
  # Step 19 — wipe-detection. SoulLink::WipeCoordinator stamps
  # `wiped_at = Time.current` when a Mark Dead transition leaves a player
  # with zero alive Pokemon (and that player has caught at least one).
  # `read_only?` (`wiped_at.present? && !completed?`) gates dashboard
  # affordances. No index — the column is read alongside `completed_at`
  # on the active run via existing single-row lookup paths.
  def change
    add_column :soul_link_runs, :wiped_at, :datetime
  end
end
