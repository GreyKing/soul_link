class SoulLinkEmulatorSession < ApplicationRecord
  STATUSES = %w[pending generating ready failed].freeze

  class AlreadyClaimedError < StandardError; end

  belongs_to :soul_link_run

  validates :status, inclusion: { in: STATUSES }
  validates :seed, presence: true
  validates :discord_user_id, uniqueness: { scope: :soul_link_run_id, allow_nil: true }

  scope :ready, -> { where(status: "ready") }
  scope :unclaimed, -> { where(discord_user_id: nil) }
  scope :claimed, -> { where.not(discord_user_id: nil) }

  def ready?
    status == "ready"
  end

  def claimed?
    discord_user_id.present?
  end

  def rom_full_path
    Rails.root.join(rom_path) if rom_path.present?
  end

  # SQL-atomic claim. The `discord_user_id: nil` guard in the WHERE clause
  # ensures concurrent claims race at the database level — exactly one
  # UPDATE will affect a row; the rest see zero affected rows and raise.
  def claim!(uid)
    rows = self.class.where(id: id, discord_user_id: nil).update_all(discord_user_id: uid)
    raise AlreadyClaimedError, "session #{id} already claimed" if rows.zero?
    reload
  end
end
