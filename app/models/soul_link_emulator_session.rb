require "zlib"
require "stringio"

class SoulLinkEmulatorSession < ApplicationRecord
  STATUSES = %w[pending generating ready failed].freeze

  # Standard gzip header. Used to distinguish gzipped values (everything
  # written by this model) from any legacy plaintext that may exist in older
  # rows from before this coder shipped.
  GZIP_MAGIC = "\x1f\x8b".b.freeze

  class AlreadyClaimedError < StandardError; end

  # Transparent gzip compression of the save_data BLOB. Pokemon Platinum SRAM
  # is ~512KB raw, mostly zero-padded — gzipping pulls that down to roughly
  # 50-80KB on typical save dumps. Stays fully opaque to EmulatorJS: the
  # client sends/receives raw bytes; the coder handles the transform.
  #
  # The coder must handle every shape AR may hand it: `nil` (column unset),
  # `""` (empty payload from a fresh save), and pre-coder plaintext (defensive
  # only — nothing should be in this state).
  module GzipCoder
    def self.dump(value)
      return nil if value.nil?
      bytes = value.to_s.b
      return bytes if bytes.empty? # Don't gzip an empty buffer — round-trips as ""

      io = StringIO.new
      io.set_encoding(Encoding::BINARY)
      gz = Zlib::GzipWriter.new(io)
      gz.write(bytes)
      gz.close
      io.string
    end

    def self.load(value)
      return nil if value.nil?
      bytes = value.is_a?(String) ? value : value.to_s
      bytes = bytes.b
      return bytes if bytes.empty?
      # Defensive: pre-coder plaintext rows pass through. Once verified that
      # all production rows are gzipped, this branch can be removed — but it
      # cheaply protects against rollback / partial migration.
      return bytes unless bytes.start_with?(GZIP_MAGIC)
      Zlib::GzipReader.new(StringIO.new(bytes)).read.b
    end
  end

  serialize :save_data, coder: GzipCoder

  belongs_to :soul_link_run

  validates :status, inclusion: { in: STATUSES }
  validates :seed, presence: true
  validates :discord_user_id, uniqueness: { scope: :soul_link_run_id, allow_nil: true }

  after_destroy :delete_rom_file

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

  # Global Action Replay cheats for this run. Sourced from
  # `config/soul_link/cheats.yml` via `SoulLink::GameState.cheats`. Returns
  # an Array of cheat hashes (`{name:, code:, enabled:}`); an empty Array
  # when no cheats are configured. Cheats are global, not per-player.
  def cheats
    list = SoulLink::GameState.cheats.fetch("action_replay", [])
    return [] unless list.is_a?(Array)
    list
  end

  # SQL-atomic claim. The `discord_user_id: nil` guard in the WHERE clause
  # ensures concurrent claims race at the database level — exactly one
  # UPDATE will affect a row; the rest see zero affected rows and raise.
  def claim!(uid)
    rows = self.class.where(id: id, discord_user_id: nil).update_all(discord_user_id: uid)
    raise AlreadyClaimedError, "session #{id} already claimed" if rows.zero?
    reload
  end

  private

  # Removes the on-disk ROM when the session is destroyed. File cleanup is
  # best-effort and MUST NOT roll back the AR transaction. `Errno::ENOENT`
  # (TOCTOU race against another cleanup), `Errno::EACCES` (permissions),
  # `Errno::EBUSY` (file locked) and similar disk-level errors all leave the
  # row deleted and the file orphaned — preferable to a half-deleted cascade
  # where rows are gone but ROMs persist. The cleanup rake task sweeps any
  # orphans on a schedule.
  def delete_rom_file
    path = rom_full_path
    path.delete if path&.exist?
  rescue StandardError => e
    Rails.logger.warn("delete_rom_file: #{e.class}: #{e.message} (rom_path=#{rom_path.inspect})")
  end
end
