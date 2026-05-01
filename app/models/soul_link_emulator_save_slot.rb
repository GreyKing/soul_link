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

  # Real-time UX: when this slot's parsed_* fields change (after the parse
  # job writes them), broadcast a Turbo Stream replace targeting the
  # owning session's roster card on the emulator page. Other players in
  # the same run see the update without a page reload.
  #
  # Two distinct method names so Rails doesn't dedupe a single callback
  # registration across the two lifecycle events (registering the same
  # method on both `after_create_commit` and `after_update_commit` only
  # the second registration sticks).
  after_create_commit :broadcast_roster_card_on_create
  after_update_commit :broadcast_roster_card_on_update, if: :saved_change_to_parsed?

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

  def saved_change_to_parsed?
    saved_change_to_attribute?("parsed_trainer_name") ||
      saved_change_to_attribute?("parsed_money") ||
      saved_change_to_attribute?("parsed_play_seconds") ||
      saved_change_to_attribute?("parsed_badges") ||
      saved_change_to_attribute?("parsed_at")
  end

  def broadcast_roster_card_on_create
    broadcast_roster_card
  end

  def broadcast_roster_card_on_update
    broadcast_roster_card
  end

  def broadcast_roster_card
    session = soul_link_emulator_session
    return unless session
    run = session.soul_link_run
    return unless run
    Turbo::StreamsChannel.broadcast_replace_to(
      run, :emulator,
      target: "emulator_roster_session_#{session.id}",
      partial: "emulator/run_sidebar_card",
      locals: { s: session }
    )
  end
end
