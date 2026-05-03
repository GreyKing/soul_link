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

  # Step 16 — broadcast a Turbo refresh on every run change so that when
  # `HallOfFameCoordinator` updates `completed_at`, the dashboard
  # refreshes and the "🏆 COMPLETE" banner appears in real time.
  # Mirrors the Step 15 `GymResult` pattern — the dashboard show.html.erb
  # already has `<%= turbo_stream_from @run, :dashboard %>` to receive it.
  broadcasts_refreshes_to ->(record) { [ record, :dashboard ] }

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

  # Step 16 — Hall of Fame run-completion. Set by
  # `SoulLink::HallOfFameCoordinator` when all 4 sessions report
  # `parsed_hof_count >= 1`. The `active` flag is intentionally NOT
  # auto-flipped (PO follow-on call). Direct AR
  # `update!(completed_at: nil)` is the un-completion path.
  def completed?
    completed_at.present?
  end

  # Step 16 — TID/SID mix-up detection (read-side).
  #
  # Returns `Array<Array<Integer>>` — each inner array is a list of
  # session ids whose active slots share the same `(parsed_trainer_id,
  # parsed_secret_id)` pair. Empty when every session has a unique or
  # unset TID. Used by the dashboard to surface a "⚠ TID conflict"
  # pill on each affected save-slot card.
  #
  # Sessions with nil/zero TID are excluded (unparsed, not a conflict
  # — a freshly-onboarded run with 0 saves shouldn't pill 4× warnings).
  # Pair key is `[trainer_id, secret_id]` so two players with the same
  # TID but different SIDs are NOT flagged (different save anyway).
  #
  # No coordinator action — the player resolves manually (could be a
  # legitimate save-reset, not a mix-up).
  def tid_conflict_groups
    pairs = soul_link_emulator_sessions
      .includes(:save_slots)
      .filter_map do |s|
        slot = s.active_slot
        next if slot.nil?
        next if slot.parsed_trainer_id.to_i.zero?
        [ slot.parsed_trainer_id, slot.parsed_secret_id, s.id ]
      end

    pairs
      .group_by { |tid, sid, _session_id| [ tid, sid ] }
      .values
      .select { |group| group.size >= 2 }
      .map    { |group| group.map { |_, _, session_id| session_id } }
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
