# Per-(run, gym) suppression record created when a player manually
# UNMARK-s a gym. While a suppression exists, `GymBeatenCoordinator`
# refuses to auto-mark that gym from save-data parses, even when all
# four players' active save slots show the badge.
#
# Suppression persists until the user explicitly re-engages by manually
# MARK-BEATEN-ing the same gym (which clears the row), or by completing
# a draft for that gym number (which also clears it). See Step 15
# brief Layer E for the full integration story.
class GymAutoMarkSuppression < ApplicationRecord
  belongs_to :soul_link_run

  validates :gym_number, presence: true,
            inclusion: { in: 1..8 },
            uniqueness: { scope: :soul_link_run_id }
end
