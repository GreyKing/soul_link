module SoulLink
  # Generates a standalone randomized ROM for the on-demand download button.
  # Unlike GenerateRunRomsJob this is not tied to an emulator session — the
  # output is a one-off file the player downloads and runs elsewhere.
  class GenerateRomDownloadJob < ApplicationJob
    queue_as :default

    OUTPUT_DIR  = Rails.root.join("storage", "roms", "downloads")
    ERROR_LIMIT = 255  # error_message is varchar(255)

    def perform(download_id)
      download = SoulLinkRomDownload.find_by(id: download_id)
      return if download.nil?

      download.update!(status: "generating", error_message: nil)

      output_path = OUTPUT_DIR.join("run_#{download.soul_link_run_id}", "#{download.id}.nds")
      ok, error = SoulLink::RomRandomizer.generate_to(output_path)

      if ok
        download.update!(
          status: "ready",
          rom_path: output_path.relative_path_from(Rails.root).to_s,
          error_message: nil
        )
      else
        download.update!(status: "failed", error_message: error.to_s[0, ERROR_LIMIT])
      end
    rescue StandardError => e
      Rails.logger.error("GenerateRomDownloadJob failed: #{e.class} #{e.message}")
      download&.update(status: "failed", error_message: e.message.to_s[0, ERROR_LIMIT])
    end
  end
end
