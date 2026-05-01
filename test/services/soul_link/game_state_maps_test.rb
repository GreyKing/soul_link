require "test_helper"
require "tempfile"

module SoulLink
  class GameStateMapsTest < ActiveSupport::TestCase
    # `SoulLink::GameState.maps` memoizes in a class-level `@maps` ivar.
    # Reset before AND after each test so this file is hermetic regardless
    # of test order. Same pattern as game_state_cheats_test.rb.
    setup do
      SoulLink::GameState.instance_variable_set(:@maps, nil)
      @real_maps_path = SoulLink::GameState::MAPS_PATH
    end

    teardown do
      SoulLink::GameState.instance_variable_set(:@maps, nil)
      if @real_maps_path && SoulLink::GameState::MAPS_PATH != @real_maps_path
        SoulLink::GameState.send(:remove_const, :MAPS_PATH)
        SoulLink::GameState.const_set(:MAPS_PATH, @real_maps_path)
      end
    end

    # Helper: redefine SoulLink::GameState::MAPS_PATH to point at `path`.
    def with_maps_path(path)
      SoulLink::GameState.send(:remove_const, :MAPS_PATH)
      SoulLink::GameState.const_set(:MAPS_PATH, Pathname.new(path))
      yield
    ensure
      SoulLink::GameState.instance_variable_set(:@maps, nil)
      SoulLink::GameState.send(:remove_const, :MAPS_PATH)
      SoulLink::GameState.const_set(:MAPS_PATH, @real_maps_path)
    end

    test "maps returns {} when the file is absent" do
      with_maps_path("/tmp/__definitely_not_a_real_maps_file__.yml") do
        refute File.exist?(SoulLink::GameState::MAPS_PATH), "test setup error: temp path exists"
        assert_equal({}, SoulLink::GameState.maps)
      end
    end

    test "map_name returns the canonical name for a known integer ID" do
      Tempfile.open([ "maps", ".yml" ]) do |f|
        f.write(<<~YAML)
          1:  { name: "Twinleaf Town" }
          8:  { name: "Eterna City" }
          80: { name: "Oreburgh Mine" }
        YAML
        f.flush

        with_maps_path(f.path) do
          assert_equal "Eterna City", SoulLink::GameState.map_name(8)
          assert_equal "Twinleaf Town", SoulLink::GameState.map_name(1)
          assert_equal "Oreburgh Mine", SoulLink::GameState.map_name(80)
        end
      end
    end

    test "map_name returns nil for an unknown ID" do
      Tempfile.open([ "maps", ".yml" ]) do |f|
        f.write("1: { name: \"Twinleaf Town\" }\n")
        f.flush

        with_maps_path(f.path) do
          assert_nil SoulLink::GameState.map_name(99999)
        end
      end
    end

    test "map_name returns nil for nil input without raising" do
      with_maps_path(@real_maps_path.to_s) do
        assert_nil SoulLink::GameState.map_name(nil)
      end
    end

    test "map_name coerces numeric-string input to integer" do
      Tempfile.open([ "maps", ".yml" ]) do |f|
        f.write("8: { name: \"Eterna City\" }\n")
        f.flush

        with_maps_path(f.path) do
          assert_equal "Eterna City", SoulLink::GameState.map_name("8")
        end
      end
    end

    test "maps memoizes — the file is read only once across multiple calls" do
      Tempfile.open([ "maps", ".yml" ]) do |f|
        f.write("1: { name: \"Twinleaf Town\" }\n")
        f.flush

        with_maps_path(f.path) do
          # Stub File.exist? to count invocations on our maps path. The
          # loader checks existence on first call; subsequent calls hit
          # the memo and skip the existence check. Same technique as
          # game_state_cheats_test.rb (Bootsnap intercepts YAML.load_file
          # so we can't count YAML loads directly).
          maps_path_str = SoulLink::GameState::MAPS_PATH.to_s
          original_exist = File.method(:exist?)
          existence_checks = 0
          exist_stub = lambda do |path|
            existence_checks += 1 if path.to_s == maps_path_str
            original_exist.call(path)
          end

          File.stub(:exist?, exist_stub) do
            3.times { SoulLink::GameState.maps }
          end

          assert_equal 1, existence_checks,
                       "expected the loader to consult the filesystem exactly once across three calls (memoization)"
        end
      end
    end

    test "reload! clears the maps cache" do
      Tempfile.open([ "maps", ".yml" ]) do |f|
        f.write("1: { name: \"Twinleaf Town\" }\n")
        f.flush

        with_maps_path(f.path) do
          assert_equal "Twinleaf Town", SoulLink::GameState.map_name(1)
          # Mutate the file's contents on disk; without reload! the memo
          # serves the stale value.
          File.write(f.path, "1: { name: \"Renamed\" }\n")
          SoulLink::GameState.reload!
          assert_equal "Renamed", SoulLink::GameState.map_name(1)
        end
      end
    end

    test "the real maps.yml file ships with at least the gym towns" do
      # Sanity check on the production file — without redefining MAPS_PATH.
      # If the file ever loses these canonical entries, the run-roster
      # surface stops showing meaningful map names.
      SoulLink::GameState.instance_variable_set(:@maps, nil)
      assert_equal "Eterna City", SoulLink::GameState.map_name(8)
      assert_equal "Oreburgh City", SoulLink::GameState.map_name(7)
      assert_equal "Snowpoint City", SoulLink::GameState.map_name(14)
    end
  end
end
