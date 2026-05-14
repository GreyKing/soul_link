class GymPoll < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  STATUSES = %w[open locked].freeze

  validates :status, inclusion: { in: STATUSES }

  class EmptyTemplateError < StandardError; end

  after_initialize :set_defaults, if: :new_record?

  # ── Class methods ──
  def self.materialize_slots(run, now: Time.current)
    template_slots = run.schedule_template&.dig("slots")
    raise EmptyTemplateError, "Run has no schedule_template configured" if template_slots.blank?

    tz       = ActiveSupport::TimeZone[run.timezone]
    zone_now = now.in_time_zone(tz)

    # Sunday rollover: the "current calendar week" would end today —
    # roll forward to next Mon-Sun for a fully forward-looking poll.
    effective = zone_now.sunday? ? zone_now + 1.day : zone_now
    monday    = effective.beginning_of_week(:monday).to_date

    template_slots.each_with_index.map do |slot, idx|
      target_date  = monday + ((slot["day_of_week"].to_i - 1) % 7).days
      hour, minute = slot["time_of_day"].split(":").map(&:to_i)
      scheduled_at = tz.local(target_date.year, target_date.month, target_date.day, hour, minute)
      { "index" => idx, "scheduled_at" => scheduled_at.utc.iso8601 }
    end
  end

  # ── Status helpers ──
  def open?   = status == "open"
  def locked? = status == "locked"

  # ── Data access ──
  def data
    (state_data || {}).with_indifferent_access
  end

  def slots
    (data["slots"] || []).map(&:with_indifferent_access)
  end

  def votes
    data["votes"] || {}
  end

  private

  def set_defaults
    self.state_data ||= { "slots" => [], "votes" => {} }
    self.status     ||= "open"
  end
end
