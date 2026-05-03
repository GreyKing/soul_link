require "test_helper"
require "tempfile"

module SoulLink
  # Mirrors `game_state_maps_test.rb`'s shape but for the new Step 17
  # met-locations table. Asserts the public API + the production-file
  # canary that gym towns + Route 201 + key dungeons + at least one
  # event-flagged ID actually ship.
  class GameStateMetLocationsTest < ActiveSupport::TestCase
    setup do
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      @real_path = SoulLink::GameState::MET_LOCATIONS_PATH
    end

    teardown do
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      if @real_path && SoulLink::GameState::MET_LOCATIONS_PATH != @real_path
        SoulLink::GameState.send(:remove_const, :MET_LOCATIONS_PATH)
        SoulLink::GameState.const_set(:MET_LOCATIONS_PATH, @real_path)
      end
    end

    def with_path(path)
      SoulLink::GameState.send(:remove_const, :MET_LOCATIONS_PATH)
      SoulLink::GameState.const_set(:MET_LOCATIONS_PATH, Pathname.new(path))
      yield
    ensure
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      SoulLink::GameState.send(:remove_const, :MET_LOCATIONS_PATH)
      SoulLink::GameState.const_set(:MET_LOCATIONS_PATH, @real_path)
    end

    test "met_locations returns {} when the file is absent" do
      with_path("/tmp/__definitely_not_a_real_met_locations_file__.yml") do
        refute File.exist?(SoulLink::GameState::MET_LOCATIONS_PATH)
        assert_equal({}, SoulLink::GameState.met_locations)
      end
    end

    test "met_location_name returns the canonical name for a known integer ID" do
      Tempfile.open([ "met_locations", ".yml" ]) do |f|
        f.write(<<~YAML)
          1:    { name: "Twinleaf Town" }
          16:   { name: "Route 201" }
          117:  { name: "Distortion World" }
          2002: { name: "Link Trade", event: true }
        YAML
        f.flush
        with_path(f.path) do
          assert_equal "Twinleaf Town",     SoulLink::GameState.met_location_name(1)
          assert_equal "Route 201",         SoulLink::GameState.met_location_name(16)
          assert_equal "Distortion World",  SoulLink::GameState.met_location_name(117)
          assert_equal "Link Trade",        SoulLink::GameState.met_location_name(2002)
        end
      end
    end

    test "met_location_name returns nil for unknown ID" do
      Tempfile.open([ "met_locations", ".yml" ]) do |f|
        f.write("1: { name: \"Twinleaf Town\" }\n")
        f.flush
        with_path(f.path) do
          assert_nil SoulLink::GameState.met_location_name(99999)
        end
      end
    end

    test "met_location_name returns nil for nil input without raising" do
      with_path(@real_path.to_s) do
        assert_nil SoulLink::GameState.met_location_name(nil)
      end
    end

    test "met_location_name coerces numeric-string input to integer" do
      Tempfile.open([ "met_locations", ".yml" ]) do |f|
        f.write("16: { name: \"Route 201\" }\n")
        f.flush
        with_path(f.path) do
          assert_equal "Route 201", SoulLink::GameState.met_location_name("16")
        end
      end
    end

    test "event_met_location? returns true for event-flagged IDs and false otherwise" do
      Tempfile.open([ "met_locations", ".yml" ]) do |f|
        f.write(<<~YAML)
          16:   { name: "Route 201" }
          2002: { name: "Link Trade", event: true }
        YAML
        f.flush
        with_path(f.path) do
          assert_equal true,  SoulLink::GameState.event_met_location?(2002)
          assert_equal false, SoulLink::GameState.event_met_location?(16)
          assert_equal false, SoulLink::GameState.event_met_location?(99999)
          assert_equal false, SoulLink::GameState.event_met_location?(nil)
        end
      end
    end

    test "reload! clears the met_locations cache" do
      Tempfile.open([ "met_locations", ".yml" ]) do |f|
        f.write("16: { name: \"Route 201\" }\n")
        f.flush
        with_path(f.path) do
          assert_equal "Route 201", SoulLink::GameState.met_location_name(16)
          File.write(f.path, "16: { name: \"Renamed\" }\n")
          SoulLink::GameState.reload!
          assert_equal "Renamed", SoulLink::GameState.met_location_name(16)
        end
      end
    end

    # ── Production-file canary ────────────────────────────────────────
    # If the shipped met_locations.yml ever loses these canonical
    # entries, the auto-detected catches surface stops resolving routes
    # to readable names.

    test "the real met_locations.yml ships gym towns" do
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      assert_equal "Twinleaf Town",  SoulLink::GameState.met_location_name(1)
      assert_equal "Oreburgh City",  SoulLink::GameState.met_location_name(8)
      assert_equal "Eterna City",    SoulLink::GameState.met_location_name(9)
      assert_equal "Sunyshore City", SoulLink::GameState.met_location_name(13)
      assert_equal "Pokemon League", SoulLink::GameState.met_location_name(15)
    end

    test "the real met_locations.yml ships Route 201 + Route 230" do
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      assert_equal "Route 201", SoulLink::GameState.met_location_name(16)
      assert_equal "Route 230", SoulLink::GameState.met_location_name(45)
    end

    test "the real met_locations.yml ships key Platinum-only dungeons" do
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      assert_equal "Distortion World", SoulLink::GameState.met_location_name(117)
      assert_equal "Mt. Coronet",      SoulLink::GameState.met_location_name(50)
      assert_equal "Eterna Forest",    SoulLink::GameState.met_location_name(48)
      assert_equal "Stark Mountain",   SoulLink::GameState.met_location_name(84)
    end

    test "the real met_locations.yml has at least one event-flagged ID" do
      SoulLink::GameState.instance_variable_set(:@met_locations, nil)
      # Daycare (2000) and Link Trade variants (2001/2002) are the
      # canonical PKHeX special-met IDs all flagged event:true.
      assert SoulLink::GameState.event_met_location?(2000), "Daycare4 (2000) should be flagged event:true"
      assert SoulLink::GameState.event_met_location?(2002), "LinkTrade4 (2002) should be flagged event:true"
      assert SoulLink::GameState.event_met_location?(3002), "Faraway4 (3002) should be flagged event:true"
    end
  end
end
