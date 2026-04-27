# Player-facing browser emulator. Each player visits `/emulator`, gets
# auto-assigned an unclaimed randomized ROM for the active run, and plays it
# in EmulatorJS. SRAM round-trips through `save_data` GET/PATCH.
class EmulatorController < ApplicationController
  include DiscordAuthentication

  # EmulatorJS DS core. `melonds` is the preferred Nintendo DS core in
  # EmulatorJS v4 (system "nds" maps to [melonds, desmume, desmume2015]).
  EMULATOR_CORE = "melonds".freeze

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
  end

  def rom
    return head :not_found unless @session&.ready?
    path = @session.rom_full_path
    return head :not_found unless path&.exist?

    send_file path, type: "application/octet-stream", disposition: "attachment", filename: "rom.nds"
  end

  def save_data
    if request.patch?
      return head :not_found if @session.nil?
      blob = request.body.read
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
