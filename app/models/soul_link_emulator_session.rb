class SoulLinkEmulatorSession < ApplicationRecord
  STATUSES = %w[pending generating ready failed].freeze

  class AlreadyClaimedError < StandardError; end

  belongs_to :soul_link_run

  validates :status, inclusion: { in: STATUSES }
  validates :seed, presence: true
  validates :discord_user_id, uniqueness: { scope: :soul_link_run_id, allow_nil: true }

  scope :ready, -> { where(status: "ready") }
  scope :unclaimed, -> { where(discord_user_id: nil) }
  scope :claimed, -> { where.not(discord_user_id: nil) }

  def ready?
    status == "ready"
  end

  def claimed?
    discord_user_id.present?
  end

  def rom_full_path
    Rails.root.join(rom_path) if rom_path.present?
  end

  # Global Action Replay cheats for this run. Sourced from
  # `config/soul_link/cheats.yml` via `SoulLink::GameState.cheats`. Returns
  # an Array of cheat hashes (`{name:, code:, enabled:}`); an empty Array
  # when no cheats are configured. Cheats are global, not per-player.
  def cheats
    list = SoulLink::GameState.cheats.fetch("action_replay", [])
    return [] unless list.is_a?(Array)
    list
  end

  # SQL-atomic claim. The `discord_user_id: nil` guard in the WHERE clause
  # ensures concurrent claims race at the database level — exactly one
  # UPDATE will affect a row; the rest see zero affected rows and raise.
  def claim!(uid)
    rows = self.class.where(id: id, discord_user_id: nil).update_all(discord_user_id: uid)
    raise AlreadyClaimedError, "session #{id} already claimed" if rows.zero?
    reload
  end
end
