namespace :soul_link do
  desc "Attach the most recent completed gym draft to the most recent gym result that has no draft (idempotent; DRY_RUN=1 to preview)"
  task backfill_gym_result_draft: :environment do
    dry_run = ENV["DRY_RUN"].present?

    SoulLinkRun.active.find_each do |run|
      result = run.gym_results.where(gym_draft_id: nil).order(gym_number: :desc).first
      draft = run.gym_drafts.pending_for_next_gym

      if result.nil?
        puts "run=#{run.id}: no gym result without a draft — nothing to do"
        next
      end
      if draft.nil?
        puts "run=#{run.id}: no unattached completed draft — nothing to do"
        next
      end

      snapshot = GymResult.snapshot_from_draft(draft)
      species = snapshot["groups"].flat_map { |g| g["pokemon"].map { |p| p["species"] } }
      puts "run=#{run.id}: gym #{result.gym_number} ← draft #{draft.id} (completed #{draft.updated_at}) #{species.inspect}"

      next if dry_run
      result.update!(gym_draft: draft, team_snapshot: snapshot)
      puts "run=#{run.id}: saved"
    end
  end
end
