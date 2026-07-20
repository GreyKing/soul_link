module Runs
  class RomDownloadsController < ApplicationController
    before_action :require_login

    # Statuses that mean "a subprocess is already queued or running for this
    # player". Deliberately excludes ready/failed so the guard self-releases.
    IN_FLIGHT_STATUSES = %w[pending generating].freeze

    def create
      run = find_run
      head :not_found and return unless run

      # Each generation spawns a 30s Java subprocess, so an unbounded POST is a
      # resource-exhaustion vector — the client-side `disabled` attribute stops
      # nobody scripted. Reattach to the caller's in-flight download instead of
      # queueing a duplicate: idempotent while work is running, and a player
      # who reloads mid-generation rejoins their job rather than abandoning it.
      # The guard releases as soon as the download reaches ready/failed.
      in_flight = run.soul_link_rom_downloads
                     .where(discord_user_id: current_user_id, status: IN_FLIGHT_STATUSES)
                     .order(:created_at).last
      if in_flight
        render json: { id: in_flight.id, status: in_flight.status }
        return
      end

      download = run.soul_link_rom_downloads.create!(
        discord_user_id: current_user_id,
        status: "pending"
      )
      SoulLink::GenerateRomDownloadJob.perform_later(download.id)

      render json: { id: download.id, status: download.status }
    end

    def show
      download = find_download
      head :not_found and return unless download

      render json: { id: download.id, status: download.status, error: download.error_message }
    end

    def download
      record = find_download
      head :not_found and return unless record&.ready?

      path = record.absolute_rom_path
      head :not_found and return if path.nil?

      send_file path,
                filename: "soul_link_run_#{record.soul_link_run_id}_#{record.id}.nds",
                type: "application/octet-stream"
    end

    private

    # Scoped to the requesting player — a download belongs to whoever
    # generated it.
    def find_download
      run = find_run
      return nil unless run
      run.soul_link_rom_downloads.find_by(id: params[:id], discord_user_id: current_user_id)
    end

    def find_run
      guild_id = session[:guild_id]
      return nil unless guild_id
      SoulLinkRun.for_guild(guild_id).find_by(id: params[:run_id])
    end
  end
end
