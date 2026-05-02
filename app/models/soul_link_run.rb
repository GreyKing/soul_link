class SoulLinkRun < ApplicationRecord
  has_many :soul_link_pokemon_groups, dependent: :destroy
  has_many :soul_link_pokemon, dependent: :destroy
  has_many :soul_link_teams, dependent: :destroy
  has_many :gym_drafts, dependent: :destroy
  has_many :gym_schedules, dependent: :destroy
  has_many :gym_results, dependent: :destroy
  has_many :gym_auto_mark_suppressions, dependent: :destroy
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

  # ── Discord avatar cache (Step 14) ──
  #
  # `player_avatars` is a JSON column mapping `discord_user_id` (string)
  # → avatar URL (string). Populated on each successful login by
  # `SessionsController#create` calling `upsert_avatar!` so that views
  # (notably the gym-draft candidate-card avatar pile) can render any
  # registered player's profile picture, not just the logged-in user's.

  # Returns the cached avatar URL for the given discord_user_id, or nil
  # if we haven't seen this user log in yet.
  def avatar_for(discord_user_id)
    (player_avatars || {})[discord_user_id.to_s]
  end

  # Idempotent upsert. Stores the URL keyed by stringified
  # discord_user_id. A blank URL deletes any existing entry for the
  # user (so we don't keep a stale URL after the user removes their
  # Discord avatar). No-op when the URL is unchanged so we don't churn
  # the row on every login.
  def upsert_avatar!(discord_user_id, url)
    return if discord_user_id.blank?
    current = (player_avatars || {}).dup
    if url.present?
      return if current[discord_user_id.to_s] == url
      current[discord_user_id.to_s] = url
    else
      return unless current.key?(discord_user_id.to_s)
      current.delete(discord_user_id.to_s)
    end
    update!(player_avatars: current)
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
