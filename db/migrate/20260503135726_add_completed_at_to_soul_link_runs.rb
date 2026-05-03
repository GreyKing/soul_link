class AddCompletedAtToSoulLinkRuns < ActiveRecord::Migration[8.1]
  # Step 16 — Hall of Fame run-completion detection. When all 4 sessions in
  # a run report `parsed_hof_count >= 1`, SoulLink::HallOfFameCoordinator
  # stamps `completed_at = Time.current`. The dashboard renders a
  # "🏆 COMPLETE" pill when the column is non-nil. The `active` flag is
  # NOT auto-flipped (PO follow-on call — see BUILD-LOG Known Gaps).
  def change
    add_column :soul_link_runs, :completed_at, :datetime
    add_index  :soul_link_runs, :completed_at
  end
end
