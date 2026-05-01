class SoulLinkRun < ApplicationRecord
  has_many :soul_link_pokemon_groups, dependent: :destroy
  has_many :soul_link_pokemon, dependent: :destroy
  has_many :soul_link_teams, dependent: :destroy
  has_many :gym_drafts, dependent: :destroy
  has_many :gym_schedules, dependent: :destroy
  has_many :gym_results, dependent: :destroy
  has_many :soul_link_emulator_sessions, dependent: :destroy

  validates :run_number, presence: true, uniqueness: { scope: :guild_id }
  validates :guild_id, presence: true
  validate :no_other_active_run_for_guild, if: -> { active? }

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :for_guild, ->(guild_id) { where(guild_id: guild_id) }
  scope :history, ->(guild_id) { for_guild(guild_id).inactive.order(run_number: :desc) }

  # At most one active run per guild — enforced at the DB level by a
  # virtual-column unique index on `active_guild_id` (Step 11 migration).
  # This is a single-row lookup; the `(guild_id, active)` index covers it.
  def self.current(guild_id)
    find_by(guild_id: guild_id, active: true)
  end

  # Group-based queries (primary — used by panels)
  def caught_groups
    soul_link_pokemon_groups.caught.order(position: :asc)
  end

  def dead_groups
    soul_link_pokemon_groups.dead.order(position: :asc)
  end

  # Legacy individual queries (kept for backward compatibility)
  def catches
    soul_link_pokemon.where(status: 'caught').order(created_at: :asc)
  end

  def deaths
    soul_link_pokemon.where(status: 'dead').order(died_at: :asc)
  end

  def deactivate!
    update!(active: false)
  end

  def discord_channels_configured?
    category_id.present? && general_channel_id.present? &&
      catches_channel_id.present? && deaths_channel_id.present?
  end

  # Aggregate state of the run's 4 emulator-ROM sessions.
  #   :none       — no sessions yet (not generated)
  #   :failed     — at least one session is in failed state (priority over :generating)
  #   :generating — at least one session is pending or generating, none failed
  #   :ready      — all sessions are ready
  def emulator_status
    sessions = soul_link_emulator_sessions
    return :none if sessions.empty?
    return :failed if sessions.any? { |s| s.status == "failed" }
    return :generating if sessions.any? { |s| %w[pending generating].include?(s.status) }
    :ready
  end

  def broadcast_state
    {
      id: id,
      run_number: run_number,
      active: active,
      gyms_defeated: gyms_defeated,
      caught_count: caught_groups.count,
      dead_count: dead_groups.count,
      started_at: created_at&.iso8601,
      ended_at: active? ? nil : updated_at&.iso8601,
      has_discord_channels: discord_channels_configured?,
      emulator_status: emulator_status
    }
  end

  private

  # User-friendly counterpart to the DB-level unique index on
  # active_guild_id. Without this, the constraint violation surfaces as
  # a 500 with `ActiveRecord::RecordNotUnique`; with it, callers see a
  # validation error and can branch on `record.errors`.
  def no_other_active_run_for_guild
    scope = self.class.where(guild_id: guild_id, active: true)
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?
    errors.add(:active, "another run is already active for this guild")
  end
end
