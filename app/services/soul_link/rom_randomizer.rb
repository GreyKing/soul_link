require "open3"
require "fileutils"
require "timeout"

module SoulLink
  # Wraps the Universal Pokemon Randomizer JAR to produce a per-session ROM.
  #
  # Synchronous — runs in the calling process. The job layer is responsible
  # for fan-out across the 4 sessions of a run (see GenerateRunRomsJob).
  #
  # Failure model: pre-condition and subprocess failures DO NOT raise. They
  # mutate the session (status=failed, error_message=<friendly>) and return
  # false. Only a real persistence bug surfaces as GenerationError.
  class RomRandomizer
    JAR_PATH           = Rails.root.join("lib", "randomizer", "randomizer.jar")
    BASE_ROM_PATH      = Rails.root.join("storage", "roms", "base", "platinum.nds")
    SETTINGS_PATH      = Rails.root.join("config", "soul_link", "randomizer_settings.rnqs")
    OUTPUT_DIR         = Rails.root.join("storage", "roms", "randomized")
    GENERATION_TIMEOUT = 30 # seconds — the JAR is fast on a modern VPS; well under any user wait.
    # Architect brief asked for 500 chars, but the `error_message` column is a
    # plain string (varchar 255 in MySQL). Cap to the column limit so a verbose
    # randomizer crash never blocks save. Flagged for Architect in REVIEW-REQUEST.
    STDERR_LIMIT       = 255

    class GenerationError < StandardError; end

    def initialize(session)
      @session = session
    end

    # Returns true on success, false on handled failure.
    def call
      reason = precondition_error
      return fail!(reason) if reason

      output_path = build_output_path
      FileUtils.mkdir_p(output_path.dirname)

      mark_generating!

      stdout, stderr, status = run_subprocess(output_path)

      if status&.success?
        finish_ready!(output_path)
        true
      else
        fail!(stderr.to_s.strip[0, STDERR_LIMIT].presence || "Randomizer exited non-zero")
      end
    rescue Timeout::Error
      fail!("Generation timed out after #{GENERATION_TIMEOUT}s")
    end

    private

    attr_reader :session

    def precondition_error
      return "Java is not installed on the server"        unless java_available?
      return "Base ROM is missing at #{BASE_ROM_PATH}"    unless File.exist?(BASE_ROM_PATH)
      return "Randomizer JAR is missing at #{JAR_PATH}"   unless File.exist?(JAR_PATH)
      return "Randomizer settings missing at #{SETTINGS_PATH}" unless File.exist?(SETTINGS_PATH)
      nil
    end

    # Defensive: re-checked on every call. The VPS may lose Java between
    # generations (package upgrades, container restarts) and we want a clean
    # error rather than a cryptic ENOENT from Open3.
    def java_available?
      system("command -v java > /dev/null 2>&1")
    end

    def build_output_path
      OUTPUT_DIR.join("run_#{session.soul_link_run_id}", "session_#{session.id}.nds")
    end

    def run_subprocess(output_path)
      Timeout.timeout(GENERATION_TIMEOUT) do
        Open3.capture3(
          "java",
          "-jar", JAR_PATH.to_s,
          "-i", BASE_ROM_PATH.to_s,
          "-o", output_path.to_s,
          "-s", SETTINGS_PATH.to_s,
          "-seed", session.seed.to_s
        )
      end
    end

    def mark_generating!
      session.status = "generating"
      session.error_message = nil
      persist!
    end

    def finish_ready!(output_path)
      session.rom_path      = output_path.relative_path_from(Rails.root).to_s
      session.status        = "ready"
      session.error_message = nil
      persist!
    end

    def fail!(message)
      session.status        = "failed"
      session.error_message = message
      persist!
      false
    end

    def persist!
      session.save!
    rescue ActiveRecord::RecordInvalid, ActiveRecord::ActiveRecordError => e
      raise GenerationError, "could not persist session #{session.id}: #{e.message}"
    end
  end
end
