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
        cleared_saves += 1 if session.save_data.present?

        # `update_columns` skips validations *and* the `after_destroy`
        # callback. We delete the file explicitly above; we do not want a
        # second deletion path firing.
        session.update_columns(rom_path: nil, save_data: nil)
      end

      # Try to remove the now-empty run dir. Non-empty dirs (shouldn't
      # happen but defensive) are left alone — `rmdir` raises on those.
      run_dir = Rails.root.join("storage", "roms", "randomized", "run_#{run.id}")
      run_dir.rmdir if run_dir.exist? && run_dir.children.empty?
    end

    puts "Cleaned #{deleted_files} ROM file(s) and #{cleared_saves} save(s) from #{inactive_runs.count} inactive run(s)."
  end
end
