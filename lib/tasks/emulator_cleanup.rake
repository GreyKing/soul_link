namespace :soul_link do
  desc "Delete ROM files and save data for inactive runs"
  task cleanup_roms: :environment do
    deleted_files = 0
    cleared_saves = 0
    inactive_runs = SoulLinkRun.inactive

    inactive_runs.find_each do |run|
      run.soul_link_emulator_sessions.find_each do |session|
        if session.rom_full_path&.exist?
          session.rom_full_path.delete
          deleted_files += 1
        end

        # Save data lives in SoulLinkEmulatorSaveSlot rows now (1..5 per
        # session). Count any slot with non-blank bytes as a cleared save,
        # then wipe all slots and clear the active pointer.
        session_slot_count = session.save_slots.where.not(save_data: nil).count
        cleared_saves += session_slot_count
        session.save_slots.destroy_all

        # `update_columns` skips validations *and* the `after_destroy`
        # callback. We delete the file explicitly above; we do not want a
        # second deletion path firing.
        session.update_columns(rom_path: nil, active_save_slot: nil)
      end

      # Try to remove the now-empty run dir. Non-empty dirs (shouldn't
      # happen but defensive) are left alone — `rmdir` raises on those.
      run_dir = Rails.root.join("storage", "roms", "randomized", "run_#{run.id}")
      run_dir.rmdir if run_dir.exist? && run_dir.children.empty?
    end

    puts "Cleaned #{deleted_files} ROM file(s) and #{cleared_saves} save(s) from #{inactive_runs.count} inactive run(s)."
  end

  desc "Prune downloaded ROMs older than 7 days"
  task prune_rom_downloads: :environment do
    cutoff = 7.days.ago
    pruned = 0

    SoulLinkRomDownload.where("created_at < ?", cutoff).find_each do |download|
      path = download.absolute_rom_path
      File.delete(path) if path
      download.destroy!
      pruned += 1
    end

    puts "Pruned #{pruned} ROM download(s) older than #{cutoff.to_date}"
  end
end
