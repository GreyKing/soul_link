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
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :for_guild, ->(guild_id) { where(guild_id: guild_id) }
  scope :history, ->(guild_id) { for_guild(guild_id).inactive.order(run_number: :desc) }

  def self.current(guild_id)
    active.for_guild(guild_id).order(run_number: :desc).first
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
end
