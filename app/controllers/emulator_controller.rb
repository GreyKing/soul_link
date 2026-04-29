# Player-facing browser emulator. Each player visits `/emulator`, gets
# auto-assigned an unclaimed randomized ROM for the active run, and plays it
# in EmulatorJS. SRAM round-trips through `save_data` GET/PATCH.
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

  before_action :require_login
  before_action :set_run
  before_action :set_session, only: [ :show, :rom, :save_data ]

  # PATCH /emulator/save_data has a binary body — the standard form-CSRF
  # token can't ride along. The Stimulus controller still sends it via
  # `X-CSRF-Token` (belt-and-suspenders), but we accept the request even
  # without one.
  protect_from_forgery with: :null_session, only: [ :save_data ], if: -> { request.patch? }

  def show
    # The view renders one of six states based on @run / @session.
    # Only the :ready branch renders the emulator stage, so only that branch
    # needs the cheats payload — populate the ivar accordingly.
    @cheats = @session.cheats if @session&.ready?

    # Run roster sidebar (Tier 1 — existing model data only). Loaded only on
    # the ready branch since that's the only state that renders the sidebar;
    # avoids a wasted query on the empty-state pages. `.order(:id)` keeps the
    # four cards in stable order across page reloads.
    @run_sessions = @run.soul_link_emulator_sessions.order(:id) if @session&.ready?
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
    if request.patch?
      return head :not_found if @session.nil?

      # Belt-and-suspenders size guard. We check the advertised content_length
      # *before* reading the body so a hostile client can't stream a 500MB
      # body and OOM the worker. Then we check the actual bytesize after
      # reading — clients can lie about content_length, or use chunked
      # encoding without one. Both checks return 413 (Payload Too Large).
      if request.content_length && request.content_length > MAX_SAVE_DATA_BYTES
        return head :content_too_large
      end

      blob = request.body.read
      return head :content_too_large if blob.bytesize > MAX_SAVE_DATA_BYTES

      @session.update!(save_data: blob)
      head :no_content
    else
      data = @session&.save_data
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
