require "test_helper"
require "tempfile"

module SoulLink
  # Mirrors `game_state_met_locations_test.rb`'s shape but for Step 19's
  # move-names lookup. Asserts the public API + the production-file
  # canary for the three sample IDs called out in the brief.
  class GameStateMoveNamesTest < ActiveSupport::TestCase
    setup do
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      @real_path = SoulLink::GameState::MOVE_NAMES_PATH
    end

    teardown do
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      if @real_path && SoulLink::GameState::MOVE_NAMES_PATH != @real_path
        SoulLink::GameState.send(:remove_const, :MOVE_NAMES_PATH)
        SoulLink::GameState.const_set(:MOVE_NAMES_PATH, @real_path)
      end
    end

    def with_path(path)
      SoulLink::GameState.send(:remove_const, :MOVE_NAMES_PATH)
      SoulLink::GameState.const_set(:MOVE_NAMES_PATH, Pathname.new(path))
      yield
    ensure
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      SoulLink::GameState.send(:remove_const, :MOVE_NAMES_PATH)
      SoulLink::GameState.const_set(:MOVE_NAMES_PATH, @real_path)
    end

    test "move_names returns {} when the file is absent" do
      with_path("/tmp/__definitely_not_a_real_move_names_file__.yml") do
        refute File.exist?(SoulLink::GameState::MOVE_NAMES_PATH)
        assert_equal({}, SoulLink::GameState.move_names)
      end
    end

    test "move_name returns the canonical name for a known integer ID" do
      Tempfile.open([ "move_names", ".yml" ]) do |f|
        f.write(<<~YAML)
          1:   "Pound"
          33:  "Tackle"
          467: "Shadow Force"
        YAML
        f.flush
        with_path(f.path) do
          assert_equal "Pound",        SoulLink::GameState.move_name(1)
          assert_equal "Tackle",       SoulLink::GameState.move_name(33)
          assert_equal "Shadow Force", SoulLink::GameState.move_name(467)
        end
      end
    end

    test "move_name returns nil for unknown ID" do
      Tempfile.open([ "move_names", ".yml" ]) do |f|
        f.write("1: \"Pound\"\n")
        f.flush
        with_path(f.path) do
          assert_nil SoulLink::GameState.move_name(99999)
        end
      end
    end

    test "move_name returns nil for nil input without raising" do
      with_path(@real_path.to_s) do
        assert_nil SoulLink::GameState.move_name(nil)
      end
    end

    test "move_name coerces numeric-string input to integer" do
      Tempfile.open([ "move_names", ".yml" ]) do |f|
        f.write("33: \"Tackle\"\n")
        f.flush
        with_path(f.path) do
          assert_equal "Tackle", SoulLink::GameState.move_name("33")
        end
      end
    end

    test "reload! clears the move_names cache" do
      Tempfile.open([ "move_names", ".yml" ]) do |f|
        f.write("33: \"Tackle\"\n")
        f.flush
        with_path(f.path) do
          assert_equal "Tackle", SoulLink::GameState.move_name(33)
          File.write(f.path, "33: \"Renamed\"\n")
          SoulLink::GameState.reload!
          assert_equal "Renamed", SoulLink::GameState.move_name(33)
        end
      end
    end

    # ── Production-file canary ────────────────────────────────────────
    # If the shipped move_names.yml ever loses these canonical entries,
    # the dashboard PC-box STATS pane stops resolving move IDs to readable
    # names. Three samples drawn from the brief's locked test list.

    test "the real move_names.yml ships move ID 1 (Pound)" do
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      assert_equal "Pound", SoulLink::GameState.move_name(1)
    end

    test "the real move_names.yml ships move ID 33 (Tackle)" do
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      assert_equal "Tackle", SoulLink::GameState.move_name(33)
    end

    test "the real move_names.yml ships move ID 467 (Shadow Force)" do
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      assert_equal "Shadow Force", SoulLink::GameState.move_name(467)
    end

    test "move ID 0 is intentionally absent (no-move sentinel)" do
      SoulLink::GameState.instance_variable_set(:@move_names, nil)
      assert_nil SoulLink::GameState.move_name(0)
    end
  end
end
