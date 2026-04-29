require "test_helper"
require "fileutils"

module SoulLink
  class RomRandomizerTest < ActiveSupport::TestCase
    # We never let real Java run, never write real ROMs, never check real
    # filesystem state for paths the production code cares about. Each test
    # composes the stubs it needs from these helpers.

    setup do
      @run     = create(:soul_link_run)
      @session = create(:soul_link_emulator_session, soul_link_run: @run, status: "pending", seed: "deadbeef")
      @service = SoulLink::RomRandomizer.new(@session)
    end

    # ---- helpers -----------------------------------------------------------

    # Stub the four pre-condition checks so they all pass by default. Any
    # individual test that wants one to fail overrides via the `missing:` key.
    #
    # `missing:` accepts :java, :base, :jar, :settings — exactly one at a time.
    #
    # Notes on the stubbing seams:
    # * `java_available?` is a private method on the service — we stub the
    #   instance method on `@service` directly. Stubbing the global `Kernel`
    #   `system` is unreliable because Ruby resolves `system` via the Kernel
    #   mixin on the receiver, not through `Kernel.system`.
    # * `File.exist?` runs constantly in Rails internals, so the stub MUST
    #   pass through unrelated paths to the real implementation.
    def with_preconditions(missing: nil)
      java_ok = missing != :java

      original_exist = File.method(:exist?)
      exist_stub = lambda do |path|
        case Pathname.new(path.to_s).cleanpath.to_s
        when SoulLink::RomRandomizer::BASE_ROM_PATH.to_s then missing != :base
        when SoulLink::RomRandomizer::JAR_PATH.to_s      then missing != :jar
        when SoulLink::RomRandomizer::SETTINGS_PATH.to_s then missing != :settings
        else original_exist.call(path)
        end
      end

      @service.stub(:java_available?, java_ok) do
        File.stub(:exist?, exist_stub) do
          yield
        end
      end
    end

    # Successful exit-status double — `Process::Status` cannot be allocated
    # directly in tests; build a minimal stand-in with the methods our service
    # actually uses (`#success?`).
    def fake_status(success)
      Struct.new(:success?).new(success)
    end

    # Skip every real mkdir during these tests — the service builds paths
    # under Rails.root that we don't want polluting the working tree.
    def with_mkdir_stub(&block)
      FileUtils.stub(:mkdir_p, ->(*_args) { nil }, &block)
    end

    # ---- precondition failures --------------------------------------------

    test "Java missing fails the session with a friendly message" do
      with_preconditions(missing: :java) do
        assert_equal false, @service.call
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/java/i, @session.error_message)
      assert_nil @session.rom_path
    end

    test "Base ROM missing fails the session" do
      with_preconditions(missing: :base) do
        assert_equal false, @service.call
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/base rom/i, @session.error_message)
    end

    test "Randomizer JAR missing fails the session" do
      with_preconditions(missing: :jar) do
        assert_equal false, @service.call
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/jar/i, @session.error_message)
    end

    test "settings file missing fails the session" do
      with_preconditions(missing: :settings) do
        assert_equal false, @service.call
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/settings/i, @session.error_message)
    end

    # Pre-condition failures must not invoke the JAR. We stub the entire
    # `run_subprocess` seam — that's now where the spawn lives.
    test "precondition failure does not call run_subprocess" do
      called = false
      run_spy = ->(*_args) { called = true; [ "", "", fake_status(true) ] }
      with_preconditions(missing: :java) do
        @service.stub(:run_subprocess, run_spy) do
          @service.call
        end
      end
      assert_equal false, called, "run_subprocess should not be invoked when preconditions fail"
    end

    # ---- happy path --------------------------------------------------------

    test "successful generation marks the session ready and stores a relative rom_path" do
      mkdir_calls = []
      mkdir_spy = ->(path) { mkdir_calls << path.to_s }

      run_args = nil
      run_stub = lambda do |output_path|
        # Reconstruct the cmd_args the production code would have built so we
        # can assert on the contract. Capture from the call site by reaching
        # into the service to mimic what the real method would have spawned.
        # Note: `cli` is the first arg after `-jar` — required by PokeRandoZX
        # to skip GUI bootstrap. No `-seed` flag (CLI mode auto-seeds).
        run_args = [
          "java",
          "-jar", SoulLink::RomRandomizer::JAR_PATH.to_s,
          "cli",
          "-i", SoulLink::RomRandomizer::BASE_ROM_PATH.to_s,
          "-o", output_path.to_s,
          "-s", SoulLink::RomRandomizer::SETTINGS_PATH.to_s
        ]
        [ "randomized ok", "", fake_status(true) ]
      end

      with_preconditions do
        FileUtils.stub(:mkdir_p, mkdir_spy) do
          @service.stub(:run_subprocess, run_stub) do
            assert_equal true, @service.call
          end
        end
      end

      @session.reload
      assert_equal "ready", @session.status
      assert_nil @session.error_message
      assert_not_nil @session.rom_path

      # rom_path is RELATIVE — never starts with a slash, always under storage/.
      refute @session.rom_path.start_with?("/"), "rom_path should be relative (got #{@session.rom_path})"
      assert @session.rom_path.start_with?("storage/roms/randomized/"),
        "rom_path should be under storage/roms/randomized/ (got #{@session.rom_path})"
      assert @session.rom_path.end_with?("session_#{@session.id}.nds")

      # The output directory should have been created.
      expected_dir = Rails.root.join("storage", "roms", "randomized", "run_#{@run.id}").to_s
      assert_includes mkdir_calls, expected_dir,
        "expected mkdir_p to be called with #{expected_dir}, got #{mkdir_calls.inspect}"

      # The CLI invocation matches the documented contract.
      assert_equal "java", run_args.first
      assert_includes run_args, "-jar"
      assert_includes run_args, "cli", "must include 'cli' subcommand or PokeRandoZX launches GUI"
      assert_includes run_args, "-i"
      assert_includes run_args, "-o"
      assert_includes run_args, "-s"
      refute_includes run_args, "-seed", "PokeRandoZX CLI mode does not accept -seed; auto-seeds per invocation"
      assert_includes run_args, SoulLink::RomRandomizer::JAR_PATH.to_s
      assert_includes run_args, SoulLink::RomRandomizer::BASE_ROM_PATH.to_s
      assert_includes run_args, SoulLink::RomRandomizer::SETTINGS_PATH.to_s

      # `cli` must come immediately after `-jar <path>` — order matters to
      # PokeRandoZX. Anywhere else and it's treated as a positional arg.
      jar_idx = run_args.index("-jar")
      assert_equal "cli", run_args[jar_idx + 2],
                   "`cli` must be the first arg after `-jar <jar_path>`"
    end

    # The contract says the session is `generating` mid-call. Capture the
    # status the moment the subprocess seam fires — that's the strongest
    # hermetic check we can make without a real subprocess.
    test "session is in 'generating' status while the subprocess runs" do
      observed_status = nil
      run_stub = lambda do |*_args|
        observed_status = @session.class.find(@session.id).status
        [ "", "", fake_status(true) ]
      end

      with_preconditions do
        with_mkdir_stub do
          @service.stub(:run_subprocess, run_stub) do
            @service.call
          end
        end
      end

      assert_equal "generating", observed_status,
        "session should be flipped to 'generating' before the subprocess runs"
      assert_equal "ready", @session.reload.status
    end

    # ---- failure paths -----------------------------------------------------

    test "non-zero exit fails the session with truncated stderr" do
      run_stub = ->(*_args) { [ "", "boom: bad rom", fake_status(false) ] }

      with_preconditions do
        with_mkdir_stub do
          @service.stub(:run_subprocess, run_stub) do
            assert_equal false, @service.call
          end
        end
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_equal "boom: bad rom", @session.error_message
      assert_nil @session.rom_path
    end

    # Architect brief asked for a 500-char truncation, but the schema column
    # for `error_message` is a plain string (varchar 255 in MySQL). The
    # service caps to the column limit so a verbose crash never blocks save.
    # Flagged for Architect in REVIEW-REQUEST.
    test "non-zero exit truncates very long stderr to the column limit" do
      huge = "x" * 5_000
      run_stub = ->(*_args) { [ "", huge, fake_status(false) ] }

      with_preconditions do
        with_mkdir_stub do
          @service.stub(:run_subprocess, run_stub) do
            @service.call
          end
        end
      end

      @session.reload
      assert_equal SoulLink::RomRandomizer::STDERR_LIMIT, @session.error_message.length
    end

    test "timeout fails the session with a timeout message" do
      run_stub = ->(*_args) { raise Timeout::Error }

      with_preconditions do
        with_mkdir_stub do
          @service.stub(:run_subprocess, run_stub) do
            assert_equal false, @service.call
          end
        end
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/timed out/i, @session.error_message)
      assert_match(/#{SoulLink::RomRandomizer::GENERATION_TIMEOUT}s/, @session.error_message)
    end

    # ---- fail! resilience --------------------------------------------------
    #
    # `fail!` is the recovery path for *every* upstream error in this service —
    # if `save!` raises here, we'd leave the session stuck in `:generating`
    # with no error message and the player would see a permanent spinner. The
    # contract is: `fail!` must never bubble. Simulate a save() returning
    # false (validation failure mid-fail) and assert we logged + did not raise.

    test "fail! survives a save() returning false (does not bubble; logs)" do
      log_buffer = StringIO.new
      captured_logger = Logger.new(log_buffer)

      # Stub the session's `save` (NOT save!) to return false. We hit `fail!`
      # via the precondition path so the rest of the call chain stays simple.
      @session.stub(:save, false) do
        Rails.stub(:logger, captured_logger) do
          with_preconditions(missing: :java) do
            assert_nothing_raised do
              assert_equal false, @service.call
            end
          end
        end
      end

      assert_match(/RomRandomizer fail!/, log_buffer.string)
      assert_match(/session #{@session.id}/, log_buffer.string)
    end

    # ---- subprocess kill on timeout ---------------------------------------
    #
    # The old pattern (`Timeout.timeout { Open3.capture3 }`) raised in the
    # caller but left the Java child running — a leak under repeated timeouts.
    # The new pattern uses Process.spawn + Process.waitpid(WNOHANG) so we hold
    # the PID and can signal the child. Assert TERM (then KILL) is sent to
    # the child when the deadline passes.

    test "subprocess timeout sends SIGTERM to the child PID and fails the session" do
      fake_pid = 99999
      kill_signals = []

      # Stub the timeout to a value that still lets the polling loop tick at
      # least once before the deadline check fires.
      original_timeout = SoulLink::RomRandomizer::GENERATION_TIMEOUT
      SoulLink::RomRandomizer.send(:remove_const, :GENERATION_TIMEOUT)
      SoulLink::RomRandomizer.const_set(:GENERATION_TIMEOUT, 0)

      spawn_stub  = ->(*_args, **_opts) { fake_pid }
      # waitpid(pid, WNOHANG) returns nil while running; called with no flag
      # after KILL it returns the pid (we just no-op).
      waitpid_stub = ->(_pid, *flags) { flags.first == Process::WNOHANG ? nil : fake_pid }
      kill_stub   = ->(sig, pid) { kill_signals << [sig, pid]; 1 }
      sleep_stub  = ->(_secs) { nil }

      with_preconditions do
        with_mkdir_stub do
          Process.stub(:spawn, spawn_stub) do
            Process.stub(:waitpid, waitpid_stub) do
              Process.stub(:kill, kill_stub) do
                # `IO.pipe` returns real pipes; the close-on-ensure path
                # tolerates already-closed pipes.
                @service.stub(:sleep, sleep_stub) do
                  assert_equal false, @service.call
                end
              end
            end
          end
        end
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/timed out/i, @session.error_message)

      # TERM is the first escalation; KILL fires after the grace sleep. Assert
      # at minimum TERM was sent — the brief calls KILL "best-effort".
      sent_signals = kill_signals.map(&:first)
      assert_includes sent_signals, "TERM",
        "expected SIGTERM to be sent to the child PID on timeout (got #{kill_signals.inspect})"
    ensure
      SoulLink::RomRandomizer.send(:remove_const, :GENERATION_TIMEOUT)
      SoulLink::RomRandomizer.const_set(:GENERATION_TIMEOUT, original_timeout)
    end
  end
end
