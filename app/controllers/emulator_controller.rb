# Player-facing browser emulator. Each player visits `/emulator`, gets
# auto-assigned an unclaimed randomized ROM for the active run, and plays it
# in EmulatorJS. SRAM round-trips through `save_data` GET (reads the active
# save slot) and `/emulator/save_slots` (saves go to one of 5 slots).
class EmulatorController < ApplicationController
  include DiscordAuthentication

  # EmulatorJS DS core. `melonds` is the preferred Nintendo DS core in
  # EmulatorJS v4 (system "nds" maps to [melonds, desmume, desmume2015]).
  EMULATOR_CORE = "melonds".freeze

  # Hard cap on incoming SRAM size. Pokemon Platinum SRAM is ~512KB; the cap
  # leaves headroom for malformed dumps without letting a hostile or buggy
  # client OOM the Rails process. Limit is on RAW (uncompressed) bytes — the
  # model gzips before storage, so the on-disk MEDIUMBLOB stays well under
  # this even at the cap.
  MAX_SAVE_DATA_BYTES = 2.megabytes

  # Real DS BIOS + firmware ZIP for melonDS. EmulatorJS's NDS core checks the
  # WiFi calibration bytes inside firmware.bin during Pokemon's save-load
  # path; melonDS-WASM's auto-generated firmware leaves those FF-padded,
  # which trips Pokemon's "A communication error has occurred" message. A
  # real-hardware firmware dump fixes it. ENV var lets dev/test point at a
  # different path; production config writes firmware.zip alongside
  # /etc/soul_link/env via the deploy script.
  DEFAULT_FIRMWARE_PATH = "/etc/soul_link/firmware.zip".freeze

  before_action :require_login
  before_action :set_run
  before_action :set_session, only: [ :show, :rom, :save_data ]

  def show
    # The view renders one of six states based on @run / @session.
    # Only the :ready branch renders the emulator stage, so only that branch
    # needs the cheats payload — populate the ivar accordingly.
    @cheats = @session.cheats if @session&.ready?

    # Run roster sidebar (Tier 1 — existing model data only). Loaded only on
    # the ready branch since that's the only state that renders the sidebar;
    # avoids a wasted query on the empty-state pages. `.order(:id)` keeps the
    # four cards in stable order across page reloads. Eager-load save_slots
    # so each card can render parsed_* metadata of the active slot without
    # N+1 queries.
    if @session&.ready?
      @run_sessions = @run.soul_link_emulator_sessions
                          .includes(:save_slots)
                          .order(:id)
      # Pre-fetch the player's own slots in slot-number order for the
      # left-column sidebar. Avoids a second round-trip on render.
      @save_slots = @session.save_slots.order(:slot_number).to_a
    end
  end

  def firmware
    path = ENV.fetch("SOUL_LINK_FIRMWARE_PATH", DEFAULT_FIRMWARE_PATH)
    return head :not_found unless File.exist?(path)

    # Cache aggressively per browser session. Firmware bytes never change
    # for a given deploy; setting expires_in lets the browser skip the
    # round-trip on every page load. private = don't let intermediaries
    # cache it, since it's auth-gated.
    expires_in 1.day, public: false
    send_file path, type: "application/zip", disposition: "inline", filename: "firmware.zip"
  end

  def rom
    return head :not_found unless @session&.ready?
    path = @session.rom_full_path
    return head :not_found unless path&.exist?

    # Safety: `path` here is `@session.rom_full_path`, which joins the model's
    # `rom_path` column with `Rails.root`. `rom_path` is server-derived — it
    # is only ever written by `SoulLink::RomRandomizer` using a path
    # constructed under `OUTPUT_DIR` via `Pathname#relative_path_from(Rails.root)`,
    # never user input. If a future migration or admin script ever writes an
    # arbitrary string to `rom_path`, `send_file` becomes a file-read-anywhere
    # primitive — at that point, guard with a `path.to_s.start_with?(OUTPUT_DIR)`
    # check before this line.
    send_file path, type: "application/octet-stream", disposition: "attachment", filename: "rom.nds"
  end

  def save_data
    if request.delete?
      return head :not_found if @session.nil?

      # Player-initiated full wipe. Removes ALL slots and clears the active
      # pointer. The slot column re-renders empty on the next page load.
      @session.save_slots.destroy_all
      @session.update_column(:active_save_slot, nil)
      head :no_content
    else
      # GET — serve the active slot's bytes. The active_slot association
      # resolves to the SoulLinkEmulatorSaveSlot whose slot_number matches
      # `active_save_slot`, or nil when no active slot is set.
      data = @session&.active_slot&.save_data
      return head :no_content if data.blank?
      send_data data, type: "application/octet-stream", disposition: "attachment", filename: "save.dat"
    end
  end

  private

  def set_run
    @run = SoulLinkRun.current(session[:guild_id])
  end

  # Resolves the player's emulator session for the active run. If the player
  # hasn't claimed one yet, atomically claim the first ready+unclaimed
  # session. The `claim!` SQL guard prevents two concurrent requests from
  # both winning the same row; if our SELECT loses the race, retry once.
  def set_session
    return @session = nil if @run.nil? || @run.emulator_status == :none

    @session = @run.soul_link_emulator_sessions.find_by(discord_user_id: current_user_id)
    return if @session

    unclaimed = @run.soul_link_emulator_sessions.unclaimed.ready.first
    return @session = nil if unclaimed.nil?

    begin
      unclaimed.claim!(current_user_id)
      @session = unclaimed
    rescue SoulLinkEmulatorSession::AlreadyClaimedError
      # Another request beat us between SELECT and UPDATE. Re-query and
      # try once more; if everything is now claimed, surface the empty
      # state in the view.
      retry_unclaimed = @run.soul_link_emulator_sessions.unclaimed.ready.first
      if retry_unclaimed
        begin
          retry_unclaimed.claim!(current_user_id)
          @session = retry_unclaimed
        rescue SoulLinkEmulatorSession::AlreadyClaimedError
          @session = nil
        end
      else
        @session = nil
      end
    end
  end
end
