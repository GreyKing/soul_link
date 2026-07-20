class SoulLinkRomDownload < ApplicationRecord
  belongs_to :soul_link_run

  STATUSES = %w[pending generating ready failed].freeze

  validates :discord_user_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ready, -> { where(status: "ready") }

  def ready?  = status == "ready"
  def failed? = status == "failed"

  # Absolute path on disk, or nil when the ROM is not there — guards against
  # a rom_path pointing at a file the cleanup task already pruned.
  def absolute_rom_path
    return nil if rom_path.blank?
    path = Rails.root.join(rom_path)
    File.exist?(path) ? path : nil
  end
end
