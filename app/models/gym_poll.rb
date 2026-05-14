class GymPoll < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  STATUSES = %w[open locked].freeze

  validates :status, inclusion: { in: STATUSES }

  after_initialize :set_defaults, if: :new_record?

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
