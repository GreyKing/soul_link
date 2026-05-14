class GymPoll < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  STATUSES = %w[open locked].freeze
  VALID_RESPONSES = %w[yes maybe no].freeze

  validates :status, inclusion: { in: STATUSES }

  class EmptyTemplateError  < StandardError; end
  class LockedError          < StandardError; end
  class InvalidSlotError     < StandardError; end
  class PastSlotError        < StandardError; end
  class InvalidResponseError < StandardError; end

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

  def vote!(user_id, slot_index, response)
    raise LockedError, "Poll is locked — reset to vote again" if locked?
    raise InvalidResponseError, "Response must be yes, maybe, or no" unless VALID_RESPONSES.include?(response)

    slot = slots.find { |s| s["index"].to_i == slot_index.to_i }
    raise InvalidSlotError, "Slot #{slot_index} does not exist on this poll" unless slot
    raise PastSlotError, "Slot has already passed" if Time.iso8601(slot["scheduled_at"]) < Time.current

    user_key  = user_id.to_s
    slot_key  = slot_index.to_s
    next_data = data.deep_dup
    next_data["votes"][user_key] ||= {}
    next_data["votes"][user_key][slot_key] = response

    if all_yes_on_slot?(next_data, slot_index)
      update!(
        state_data:        next_data.as_json,
        status:            "locked",
        locked_slot_index: slot_index.to_i,
        locked_at:         Time.current
      )
    else
      update!(state_data: next_data.as_json)
    end
    true
  end

  private

  def set_defaults
    self.state_data ||= { "slots" => [], "votes" => {} }
    self.status     ||= "open"
  end

  def all_yes_on_slot?(state, slot_index)
    required = SoulLink::GameState.player_ids.map(&:to_s)
    votes    = state["votes"] || {}
    slot_key = slot_index.to_s
    required.all? { |uid| votes.dig(uid, slot_key) == "yes" }
  end
end
