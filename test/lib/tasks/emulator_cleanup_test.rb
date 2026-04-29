require "test_helper"
require "rake"

class EmulatorCleanupTaskTest < ActiveSupport::TestCase
  TASK_NAME = "soul_link:cleanup_roms".freeze

  # Tasks are loaded once per process — repeated `load_tasks` calls would
  # redefine and re-enable every task. Memoize on the class.
  @loaded = false
  class << self
    attr_accessor :loaded
  end

  # Each test runs inside a tempdir-rooted Rails sandbox so the rake task's
  # `Rails.root.join("storage", "roms", "randomized", "run_<id>")` lookup
  # resolves to throwaway space. The model's `rom_full_path` also goes
  # through `Rails.root.join`, so seeding `rom_path` as a relative segment
  # under the tempdir keeps everything consistent. Overriding `#run` (rather
  # than `setup`/`teardown` blocks) keeps the stub active for the entire
  # test body and guarantees cleanup even on failure.
  def run(*args, &block)
    @tmp_root = Pathname.new(Dir.mktmpdir("soul_link_test_storage"))
    @tmp_root.join("storage", "roms", "randomized").mkpath

    unless self.class.loaded
      Rails.application.load_tasks
      self.class.loaded = true
    end
    Rake::Task[TASK_NAME].reenable

    # `Rails.root` is `Rails.application.config.root`, NOT `Rails.application.root`,
    # so stubbing the latter is a no-op. Stubbing the module-level entry point is
    # what actually redirects every `Rails.root.join(...)` lookup into the sandbox.
    Rails.stub(:root, @tmp_root) do
      super(*args, &block)
    end
  ensure
    FileUtils.rm_rf(@tmp_root) if @tmp_root
  end

  # ── helpers ────────────────────────────────────────────────────────────

  # Create a fake ROM file under the sandboxed `run_<id>/` directory.
  # Mirrors the layout `RomRandomizer` produces.
  def create_rom_file(run, filename: "rom.nds")
    run_dir = Rails.root.join("storage", "roms", "randomized", "run_#{run.id}")
    run_dir.mkpath
    path = run_dir.join(filename)
    path.write("rom-bytes")
    path
  end

  # Convert an absolute path under `Rails.root` into the relative segment
  # we store in `rom_path`. The model joins it back with `Rails.root` via
  # `rom_full_path`.
  def relative_to_root(absolute_path)
    absolute_path.relative_path_from(Rails.root).to_s
  end

  def invoke_task
    out, _err = capture_io { Rake::Task[TASK_NAME].invoke }
    out
  end

  # ── tests ──────────────────────────────────────────────────────────────

  test "active run is untouched: rom_path, save_data, and on-disk file all preserved" do
    run = create(:soul_link_run, active: true)
    rom = create_rom_file(run)
    session = create(:soul_link_emulator_session, soul_link_run: run,
                     status: "ready", rom_path: relative_to_root(rom),
                     save_data: "some-bytes")

    invoke_task

    session.reload
    assert_equal relative_to_root(rom), session.rom_path
    assert_equal "some-bytes", session.save_data
    assert rom.exist?, "active run's ROM file should still exist on disk"
  end

  test "inactive run is cleaned: rom_path nil, save_data nil, file deleted" do
    run = create(:soul_link_run, active: false)
    rom = create_rom_file(run)
    session = create(:soul_link_emulator_session, soul_link_run: run,
                     status: "ready", rom_path: relative_to_root(rom),
                     save_data: "some-bytes")

    invoke_task

    session.reload
    assert_nil session.rom_path
    assert_nil session.save_data
    assert_not rom.exist?, "inactive run's ROM file should have been deleted"
  end

  test "inactive run with missing on-disk file: task does not raise; rom_path cleared" do
    run = create(:soul_link_run, active: false)
    # rom_path points at a path that never existed on disk.
    session = create(:soul_link_emulator_session, soul_link_run: run,
                     status: "failed",
                     rom_path: "storage/roms/randomized/run_#{run.id}/missing.nds",
                     save_data: nil)

    assert_nothing_raised { invoke_task }

    session.reload
    assert_nil session.rom_path
  end

  test "empty run dir is removed after cleanup" do
    run = create(:soul_link_run, active: false)
    rom = create_rom_file(run)
    create(:soul_link_emulator_session, soul_link_run: run, status: "ready",
                                        rom_path: relative_to_root(rom))

    run_dir = Rails.root.join("storage", "roms", "randomized", "run_#{run.id}")
    assert run_dir.exist?, "precondition: run dir must exist before cleanup"

    invoke_task

    assert_not run_dir.exist?,
      "empty run_<id>/ directory should be removed after cleanup"
  end

  test "summary line reports counts of files, saves, and inactive runs" do
    active = create(:soul_link_run, active: true)
    active_rom = create_rom_file(active)
    create(:soul_link_emulator_session, soul_link_run: active, status: "ready",
                                        rom_path: relative_to_root(active_rom))

    inactive = create(:soul_link_run, active: false)
    inactive_rom = create_rom_file(inactive)
    create(:soul_link_emulator_session, soul_link_run: inactive, status: "ready",
                                        rom_path: relative_to_root(inactive_rom),
                                        save_data: "blob")

    output = invoke_task

    assert_match(/Cleaned 1 ROM file\(s\) and 1 save\(s\) from 1 inactive run\(s\)/, output)
  end
end
