class SoulLinkEmulatorSaveSlot < ApplicationRecord
  MIN_SLOT = 1
  MAX_SLOT = 5

  # Reuses SoulLinkEmulatorSession::GzipCoder — same compression contract,
  # same edge-case handling (nil, empty, legacy plaintext). Promoting the
  # coder to its own concern is deferred unless duplication grows.
  serialize :save_data, coder: SoulLinkEmulatorSession::GzipCoder

  belongs_to :soul_link_emulator_session

  validates :slot_number, presence: true,
                          inclusion: { in: MIN_SLOT..MAX_SLOT },
                          uniqueness: { scope: :soul_link_emulator_session_id }

  # Re-parse the trainer block whenever the SRAM blob changes. The job
  # writes parsed_* fields via `update_columns` to avoid re-firing this
  # callback in a tight loop.
  after_update_commit :enqueue_parse_if_save_changed
  after_create_commit :enqueue_parse_if_save_present

  private

  def enqueue_parse_if_save_changed
    return unless saved_change_to_attribute?("save_data")
    return if save_data.blank?
    SoulLink::ParseSaveDataJob.perform_later(self)
  end

  def enqueue_parse_if_save_present
    return if save_data.blank?
    SoulLink::ParseSaveDataJob.perform_later(self)
  end
end
