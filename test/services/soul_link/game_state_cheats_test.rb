require "test_helper"
require "tempfile"

module SoulLink
  class GameStateCheatsTest < ActiveSupport::TestCase
    # `SoulLink::GameState.cheats` memoizes in a class-level `@cheats`
    # instance variable. Reset before AND after each test so this file is
    # hermetic regardless of test order or any prior caller (e.g. another
    # test that loaded the real cheats.yml off disk).
    #
    # Stubbing `YAML.load_file` doesn't work cleanly here: Bootsnap
    # `prepend`s `Bootsnap::CompileCache::YAML::Psych4::Patch` onto Psych,
    # which is checked ahead of any singleton-class stub installed by
    # `Minitest::Mock.stub`. We sidestep the issue by writing a real temp
    # YAML file and pointing the loader at it via the documented constant.
    setup do
      SoulLink::GameState.instance_variable_set(:@cheats, nil)
      @real_cheats_path = SoulLink::GameState::CHEATS_PATH
    end

    teardown do
      SoulLink::GameState.instance_variable_set(:@cheats, nil)
      # Restore the real constant in case a test redefined it.
      if @real_cheats_path && SoulLink::GameState::CHEATS_PATH != @real_cheats_path
        SoulLink::GameState.send(:remove_const, :CHEATS_PATH)
        SoulLink::GameState.const_set(:CHEATS_PATH, @real_cheats_path)
      end
    end

    # Helper: redefine SoulLink::GameState::CHEATS_PATH to point at `path`.
    # `remove_const` + `const_set` avoids the "already initialized constant"
    # warning and lets the loader use the new value transparently.
    def with_cheats_path(path)
      SoulLink::GameState.send(:remove_const, :CHEATS_PATH)
      SoulLink::GameState.const_set(:CHEATS_PATH, Pathname.new(path))
      yield
    ensure
      SoulLink::GameState.instance_variable_set(:@cheats, nil)
      SoulLink::GameState.send(:remove_const, :CHEATS_PATH)
      SoulLink::GameState.const_set(:CHEATS_PATH, @real_cheats_path)
    end

    test "cheats returns {} when the file is absent" do
      with_cheats_path("/tmp/__definitely_not_a_real_cheats_file__.yml") do
        # Sanity: ensure the path really doesn't exist.
        refute File.exist?(SoulLink::GameState::CHEATS_PATH), "test setup error: temp path exists"
        assert_equal({}, SoulLink::GameState.cheats)
      end
    end

    test "cheats returns the parsed hash when the file exists" do
      Tempfile.open([ "cheats", ".yml" ]) do |f|
        f.write(<<~YAML)
          action_replay:
            - name: "Walk Through Walls"
              enabled: true
              code: "02000000 12345678"
        YAML
        f.flush

        with_cheats_path(f.path) do
          parsed = SoulLink::GameState.cheats
          assert_equal [ "action_replay" ], parsed.keys
          assert_equal 1, parsed["action_replay"].length
          assert_equal "Walk Through Walls", parsed["action_replay"][0]["name"]
          assert_equal true, parsed["action_replay"][0]["enabled"]
          assert_equal "02000000 12345678", parsed["action_replay"][0]["code"]
        end
      end
    end

    test "cheats handles multi-line code strings via YAML pipe blocks" do
      Tempfile.open([ "cheats", ".yml" ]) do |f|
        f.write(<<~YAML)
          action_replay:
            - name: "Multi-line Cheat"
              enabled: true
              code: |
                02000000 12345678
                02000004 ABCDEF01
        YAML
        f.flush

        with_cheats_path(f.path) do
          code = SoulLink::GameState.cheats.dig("action_replay", 0, "code")
          assert_includes code, "02000000 12345678"
          assert_includes code, "02000004 ABCDEF01"
        end
      end
    end

    test "cheats memoizes — the file is read only once across multiple calls" do
      Tempfile.open([ "cheats", ".yml" ]) do |f|
        f.write("action_replay: []\n")
        f.flush

        with_cheats_path(f.path) do
          # Track every File.exist? call against our cheats path. The
          # loader checks existence on first invocation; on second + third
          # invocations the memo short-circuits the existence check
          # entirely.
          cheats_path_str = SoulLink::GameState::CHEATS_PATH.to_s
          original_exist = File.method(:exist?)
          existence_checks = 0
          exist_stub = lambda do |path|
            if path.to_s == cheats_path_str
              existence_checks += 1
              true
            else
              original_exist.call(path)
            end
          end

          File.stub(:exist?, exist_stub) do
            SoulLink::GameState.cheats
            SoulLink::GameState.cheats
            SoulLink::GameState.cheats
          end

          assert_equal 1, existence_checks,
                       "expected the loader to consult the filesystem exactly once across three calls (memoization)"
        end
      end
    end

    test "cheats returns {} when the YAML file is empty (parses to nil)" do
      Tempfile.open([ "cheats", ".yml" ]) do |f|
        f.write("") # empty file → YAML.load_file returns nil → fall back to {}
        f.flush

        with_cheats_path(f.path) do
          assert_equal({}, SoulLink::GameState.cheats)
        end
      end
    end

    test "reload! clears the memoized cheats" do
      Tempfile.open([ "cheats", ".yml" ]) do |f|
        f.write("action_replay:\n  - name: \"First\"\n    enabled: true\n    code: \"AAA\"\n")
        f.flush

        with_cheats_path(f.path) do
          first = SoulLink::GameState.cheats
          assert_equal "First", first.dig("action_replay", 0, "name")

          # Rewrite the file in place and clear the memo via reload!
          File.write(f.path, "action_replay:\n  - name: \"Second\"\n    enabled: true\n    code: \"BBB\"\n")
          SoulLink::GameState.reload!

          second = SoulLink::GameState.cheats
          assert_equal "Second", second.dig("action_replay", 0, "name")
        end
      end
    end
  end
end
