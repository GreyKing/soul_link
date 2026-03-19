class GymSchedule < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  STATUSES = %w[proposed confirmed completed cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :proposed_by, presence: true
  validates :scheduled_at, presence: true

  scope :active, -> { where(status: %w[proposed confirmed]) }
  scope :upcoming, -> { active.where("scheduled_at >= ?", Time.current).order(scheduled_at: :asc) }

  after_initialize :set_defaults, if: :new_record?

  # ── Status Helpers ──

  def proposed?()  = status == "proposed"
  def confirmed?() = status == "confirmed"
  def completed?() = status == "completed"
  def cancelled?() = status == "cancelled"

  # ── Data Access ──

  def data
    (state_data || {}).with_indifferent_access
  end

  def rsvps
    data["rsvps"] || {}
  end

  # ── Player Helpers ──

  def players
    SoulLink::GameState.players
  end

  def player_ids
    SoulLink::GameState.player_ids
  end

  def proposer_name
    SoulLink::GameState.player_name(proposed_by)
  end

  # ── RSVP Logic ──

  def rsvp!(user_id, response)
    raise "Schedule is not open for RSVPs" unless proposed? || confirmed?
    raise "Invalid RSVP response" unless %w[yes no maybe].include?(response)

    current_rsvps = rsvps.dup
    current_rsvps[user_id.to_s] = response
    update_data!("rsvps" => current_rsvps)

    auto_confirm! if all_accepted?
  end

  def rsvp_for(user_id)
    rsvps[user_id.to_s]
  end

  def all_responded?
    (player_ids.map(&:to_s) - rsvps.keys).empty?
  end

  def all_accepted?
    all_responded? && rsvps.values.all? { |v| v == "yes" }
  end

  def yes_count
    rsvps.values.count { |v| v == "yes" }
  end

  def maybe_count
    rsvps.values.count { |v| v == "maybe" }
  end

  def no_count
    rsvps.values.count { |v| v == "no" }
  end

  # ── Status Transitions ──

  def confirm!
    raise "Can only confirm a proposed schedule" unless proposed?
    update!(status: "confirmed")
  end

  def cancel!
    raise "Cannot cancel a completed schedule" if completed?
    update!(status: "cancelled")
  end

  def complete!
    raise "Can only complete a confirmed schedule" unless confirmed?
    update!(status: "completed")
  end

  # ── Broadcast State ──

  def broadcast_state
    {
      id: id,
      status: status,
      scheduled_at: scheduled_at.iso8601,
      proposed_by: proposed_by.to_s,
      proposer_name: proposer_name,
      rsvps: rsvps.transform_keys(&:to_s),
      all_responded: all_responded?,
      all_accepted: all_accepted?,
      yes_count: yes_count,
      maybe_count: maybe_count,
      no_count: no_count,
      players: players.map { |p| p.merge("discord_user_id" => p["discord_user_id"].to_s) },
      player_ids: player_ids.map(&:to_s),
      discord_message_id: discord_message_id&.to_s,
      gym_draft_id: gym_draft_id
    }
  end

  private

  def set_defaults
    self.state_data ||= { "rsvps" => {} }
    # Proposer auto-RSVPs "yes"
    if proposed_by.present?
      rsvps_hash = self.state_data["rsvps"] || {}
      rsvps_hash[proposed_by.to_s] = "yes"
      self.state_data["rsvps"] = rsvps_hash
    end
  end

  def update_data!(changes)
    update!(state_data: data.merge(changes).as_json)
  end

  def auto_confirm!
    update!(status: "confirmed") if proposed?
  end
end
