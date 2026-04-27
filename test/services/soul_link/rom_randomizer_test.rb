require "test_helper"
require "open3"
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

    # Pre-condition failures must not invoke the JAR.
    test "precondition failure does not call Open3" do
      called = false
      open3_spy = ->(*_args) { called = true; [ "", "", fake_status(true) ] }
      with_preconditions(missing: :java) do
        Open3.stub(:capture3, open3_spy) do
          @service.call
        end
      end
      assert_equal false, called, "Open3.capture3 should not be invoked when preconditions fail"
    end

    # ---- happy path --------------------------------------------------------

    test "successful generation marks the session ready and stores a relative rom_path" do
      mkdir_calls = []
      mkdir_spy = ->(path) { mkdir_calls << path.to_s }

      open3_args = nil
      open3_stub = lambda do |*args|
        open3_args = args
        [ "randomized ok", "", fake_status(true) ]
      end

      with_preconditions do
        FileUtils.stub(:mkdir_p, mkdir_spy) do
          Open3.stub(:capture3, open3_stub) do
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
      assert_equal "java", open3_args.first
      assert_includes open3_args, "-jar"
      assert_includes open3_args, "-i"
      assert_includes open3_args, "-o"
      assert_includes open3_args, "-s"
      assert_includes open3_args, "-seed"
      assert_includes open3_args, @session.seed
      assert_includes open3_args, SoulLink::RomRandomizer::JAR_PATH.to_s
      assert_includes open3_args, SoulLink::RomRandomizer::BASE_ROM_PATH.to_s
      assert_includes open3_args, SoulLink::RomRandomizer::SETTINGS_PATH.to_s
    end

    # The contract says the session is `generating` mid-call. Capture the
    # status the moment Open3 is invoked — that's the strongest hermetic
    # check we can make without a real subprocess.
    test "session is in 'generating' status while the subprocess runs" do
      observed_status = nil
      open3_stub = lambda do |*_args|
        observed_status = @session.class.find(@session.id).status
        [ "", "", fake_status(true) ]
      end

      with_preconditions do
        with_mkdir_stub do
          Open3.stub(:capture3, open3_stub) do
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
      open3_stub = ->(*_args) { [ "", "boom: bad rom", fake_status(false) ] }

      with_preconditions do
        with_mkdir_stub do
          Open3.stub(:capture3, open3_stub) do
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
      open3_stub = ->(*_args) { [ "", huge, fake_status(false) ] }

      with_preconditions do
        with_mkdir_stub do
          Open3.stub(:capture3, open3_stub) do
            @service.call
          end
        end
      end

      @session.reload
      assert_equal SoulLink::RomRandomizer::STDERR_LIMIT, @session.error_message.length
    end

    test "timeout fails the session with a timeout message" do
      open3_stub = ->(*_args) { raise Timeout::Error }

      with_preconditions do
        with_mkdir_stub do
          Open3.stub(:capture3, open3_stub) do
            assert_equal false, @service.call
          end
        end
      end

      @session.reload
      assert_equal "failed", @session.status
      assert_match(/timed out/i, @session.error_message)
      assert_match(/#{SoulLink::RomRandomizer::GENERATION_TIMEOUT}s/, @session.error_message)
    end
  end
end
