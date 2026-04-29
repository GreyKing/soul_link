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
        # Pass the raw stderr through; `fail!` truncates to the column limit.
        # Fallback string preserves the legacy contract when stderr is empty.
        fail!(stderr.to_s.strip.presence || "Randomizer exited non-zero")
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

    # Returns `[stdout, stderr, status]` where `status` is the child's
    # `Process::Status`. On timeout this method raises `Timeout::Error` (the
    # `call` flow's existing `rescue` handles the user-facing message).
    #
    # The legacy `Timeout.timeout { Open3.capture3 }` pattern raised in the
    # calling thread but left the Java child running — under repeated
    # timeouts that's a slow PID leak. The spawn+waitpid pattern below holds
    # the child PID so we can escalate TERM → KILL on the deadline.
    def run_subprocess(output_path)
      # PokeRandoZX requires the `cli` subcommand as the first argument after
      # `-jar` to skip the GUI bootstrap. Without it the JAR launches a Swing
      # JFrame, which fails on a headless server with `HeadlessException` —
      # but Java's AWT thread swallows the exception and the process exits
      # with code 0 having never written the output ROM. Hence: silent
      # generation failures with `status=ready` but no file on disk.
      #
      # CLI mode does NOT accept `-seed` (it auto-generates a seed per run).
      # Our DB `seed` column is informational only — the four sessions of a
      # run get four distinct ROMs because the JAR is invoked four times.
      cmd_args = [
        "java",
        "-jar", JAR_PATH.to_s,
        "cli",
        "-i", BASE_ROM_PATH.to_s,
        "-o", output_path.to_s,
        "-s", SETTINGS_PATH.to_s
      ]

      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe
      pid = nil

      begin
        pid = Process.spawn(*cmd_args, out: stdout_w, err: stderr_w)
        # Close the write ends in the parent so the read pipes will EOF
        # cleanly once the child exits.
        stdout_w.close
        stderr_w.close
        stdout_w = nil
        stderr_w = nil

        wait_for_subprocess(pid)

        # If we made it here, the child exited on its own. `$?` is the last
        # waited-on status from `Process.waitpid` inside the loop.
        status = $?
        stdout = read_pipe(stdout_r)
        stderr = read_pipe(stderr_r)
        [ stdout, stderr, status ]
      ensure
        # Defensive cleanup. `wait_for_subprocess` reaps on success and on
        # timeout; if anything unexpected raised between spawn and reap, kill
        # the child so we don't leak.
        if pid
          begin
            Process.kill("KILL", pid)
            Process.waitpid(pid)
          rescue Errno::ESRCH, Errno::ECHILD
            # Already gone — fine.
          end
        end
        [ stdout_r, stdout_w, stderr_r, stderr_w ].compact.each do |io|
          io.close unless io.closed?
        rescue StandardError
          # Best-effort close; swallow.
        end
      end
    end

    # Polls `Process.waitpid(pid, WNOHANG)` until the child exits or the
    # deadline passes. On deadline, escalates TERM → (grace) → KILL and
    # raises `Timeout::Error` to feed the existing `rescue` in `call`.
    def wait_for_subprocess(pid)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GENERATION_TIMEOUT
      loop do
        finished = Process.waitpid(pid, Process::WNOHANG)
        return if finished

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          terminate_subprocess(pid)
          raise Timeout::Error, "Java process exceeded #{GENERATION_TIMEOUT}s"
        end

        sleep 0.1
      end
    end

    # TERM first, then a brief grace, then KILL. Java handles TERM cleanly in
    # most cases (closes file handles, prints final stderr); KILL is the
    # forced backstop. `Errno::ESRCH` means the child already exited between
    # checks — treat as success.
    def terminate_subprocess(pid)
      Process.kill("TERM", pid)
      sleep 0.5
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      # Child raced ahead and exited; still need to reap.
    ensure
      begin
        Process.waitpid(pid)
      rescue Errno::ECHILD
        # Already reaped.
      end
    end

    # Reads a pipe to EOF in binary mode. Pipes are non-blocking-friendly
    # because the writer (child) is gone by the time we get here.
    def read_pipe(io)
      io.binmode
      io.read.to_s
    rescue IOError
      ""
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

    # Best-effort: a `fail!` call IS the recovery path for an upstream
    # exception, so it must NOT itself raise. If `save!` blew up here we'd
    # leave the session in `:generating` (or `:pending`) forever, with no
    # error_message for the player. Use plain `save` and log the failure —
    # the next regenerate will reclaim the row.
    def fail!(message)
      session.status        = "failed"
      session.error_message = truncate_error(message)
      unless session.save
        Rails.logger.error(
          "RomRandomizer fail!: could not persist failed status for session #{session.id}: " \
          "#{session.errors.full_messages.join(', ')} (intended message: #{message.inspect})"
        )
      end
      false
    end

    # Cap any inbound error string at the column limit. Centralized so all
    # callers go through the same guard — `error_message` is varchar(255) in
    # MySQL and a verbose stderr would otherwise blow up `save!`.
    def truncate_error(message)
      message.to_s.strip[0, STDERR_LIMIT].presence || "Randomizer failed without details"
    end

    def persist!
      session.save!
    rescue ActiveRecord::RecordInvalid, ActiveRecord::ActiveRecordError => e
      raise GenerationError, "could not persist session #{session.id}: #{e.message}"
    end
  end
end
