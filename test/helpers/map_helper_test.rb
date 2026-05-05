require "test_helper"

# Step 23 R4 — unit tests for `MapHelper`. The R4 redesign locks four
# new helper signatures plus a bonus on `location_status` /
# `primary_group` (existing helpers — never tested before this).
#
# Pure-function helpers — no DB beyond the factory-built groups for
# `location_status` / `primary_group` / `segment_progress`. The progression
# / gym_info / locations inputs are passed as plain Hashes shaped like
# the YAML fixtures, so the tests don't depend on the live config files.
class MapHelperTest < ActionView::TestCase
  include MapHelper

  GREY = 153665622641737728

  # ── location_status ───────────────────────────────────────────────────

  test "location_status returns uncaught for empty groups" do
    assert_equal "uncaught", location_status(nil)
    assert_equal "uncaught", location_status([])
  end

  test "location_status returns caught when any group is caught" do
    run = create(:soul_link_run)
    g1 = create(:soul_link_pokemon_group, soul_link_run: run, status: "dead",   nickname: "DEAD",  location: "route_201")
    g2 = create(:soul_link_pokemon_group, soul_link_run: run, status: "caught", nickname: "ALIVE", location: "route_201")
    assert_equal "caught", location_status([ g1, g2 ])
  end

  test "location_status returns dead when no groups caught and at least one dead" do
    run = create(:soul_link_run)
    g1 = create(:soul_link_pokemon_group, soul_link_run: run, status: "dead", nickname: "DEAD", location: "route_201")
    assert_equal "dead", location_status([ g1 ])
  end

  # ── primary_group ─────────────────────────────────────────────────────

  test "primary_group returns nil for empty groups" do
    assert_nil primary_group(nil)
    assert_nil primary_group([])
  end

  test "primary_group prefers a caught group over a dead one" do
    run = create(:soul_link_run)
    dead   = create(:soul_link_pokemon_group, soul_link_run: run, status: "dead",   nickname: "RIP",     location: "route_201")
    caught = create(:soul_link_pokemon_group, soul_link_run: run, status: "caught", nickname: "ALIVE", location: "route_201")
    assert_equal caught, primary_group([ dead, caught ])
  end

  test "primary_group falls back to the first group when none are caught" do
    run = create(:soul_link_run)
    g1 = create(:soul_link_pokemon_group, soul_link_run: run, status: "dead", nickname: "FIRST",  location: "route_201")
    g2 = create(:soul_link_pokemon_group, soul_link_run: run, status: "dead", nickname: "SECOND", location: "route_201")
    assert_equal g1, primary_group([ g1, g2 ])
  end

  # ── next_uncaught_route_key ───────────────────────────────────────────

  test "next_uncaught_route_key returns the first uncaught route across segments" do
    progression = sample_progression
    locations = sample_locations
    # route_201 caught, route_202 uncaught — should pick 202.
    groups_by_location = {
      "route_201" => [ stub_group(status: "caught") ]
    }
    assert_equal "route_202", next_uncaught_route_key(progression, locations, groups_by_location)
  end

  test "next_uncaught_route_key skips dungeons, lakes, cities, and specials" do
    progression = {
      "segments" => [
        {
          "locations" => %w[lake_verity oreburgh_mine starter route_204],
          "gym" => "first_gym"
        }
      ]
    }
    # Lake, dungeon, and special are all uncaught — skipped.
    # route_204 is the only catchable route → wins.
    assert_equal "route_204", next_uncaught_route_key(progression, sample_locations, {})
  end

  test "next_uncaught_route_key returns nil when every route is caught" do
    progression = sample_progression
    groups = {
      "route_201" => [ stub_group(status: "caught") ],
      "route_202" => [ stub_group(status: "caught") ],
      "route_204" => [ stub_group(status: "dead") ]
    }
    assert_nil next_uncaught_route_key(progression, sample_locations, groups)
  end

  test "next_uncaught_route_key prefers earlier segments over later" do
    progression = {
      "segments" => [
        { "locations" => %w[route_201], "gym" => "first_gym" },
        { "locations" => %w[route_204], "gym" => "second_gym" }
      ]
    }
    # Both uncaught — first segment wins.
    assert_equal "route_201", next_uncaught_route_key(progression, sample_locations, {})
  end

  # ── current_segment_label ─────────────────────────────────────────────

  test "current_segment_label returns FINAL STRETCH when next_uncaught_key is nil" do
    assert_equal "FINAL STRETCH", current_segment_label(sample_progression, sample_gym_info, nil)
  end

  test "current_segment_label returns the bare upcoming-gym city label" do
    # route_202 is in segment 1 (gym = first_gym = oreburgh_city).
    assert_equal "OREBURGH",
      current_segment_label(sample_progression, sample_gym_info, "route_202")
    # route_204 is in segment 2 (gym = second_gym = eterna_city).
    assert_equal "ETERNA",
      current_segment_label(sample_progression, sample_gym_info, "route_204")
  end

  test "current_segment_label returns ELITE FOUR for the null-gym segment" do
    progression = {
      "segments" => [
        { "locations" => %w[victory_road], "gym" => nil }
      ]
    }
    locations = { "victory_road" => { "name" => "Victory Road", "type" => "dungeon" } }
    # victory_road is type=dungeon, so next_uncaught_route_key returns nil
    # — but if a route were in this segment, label would be ELITE FOUR.
    label = current_segment_label(progression, sample_gym_info, "victory_road")
    assert_equal "ELITE FOUR", label
    assert_nil next_uncaught_route_key(progression, locations, {})
  end

  # ── segment_divider_label ─────────────────────────────────────────────

  test "segment_divider_label names the upcoming segment's bare city" do
    # After segment 0 (first_gym = oreburgh_city) → divider names segment 1's
    # gym = second_gym = eterna_city → "ETERNA".
    assert_equal "ETERNA", segment_divider_label(sample_progression, sample_gym_info, 0)
  end

  test "segment_divider_label returns ELITE FOUR before the null-gym segment" do
    progression = {
      "segments" => [
        { "locations" => %w[route_201], "gym" => "eighth_gym" },
        { "locations" => %w[victory_road], "gym" => nil }
      ]
    }
    assert_equal "ELITE FOUR", segment_divider_label(progression, sample_gym_info, 0)
  end

  test "segment_divider_label returns nil after the last segment" do
    assert_nil segment_divider_label(sample_progression, sample_gym_info, 99)
  end

  # ── segment_progress ──────────────────────────────────────────────────

  test "segment_progress counts only catchable types in total" do
    segment = {
      "locations" => %w[route_201 oreburgh_city oreburgh_mine lake_verity starter],
      "gym" => "first_gym"
    }
    # route + dungeon + lake + special = 4 catchable. City excluded.
    progress = segment_progress(segment, sample_locations, {})
    assert_equal({ caught: 0, total: 4 }, progress)
  end

  test "segment_progress counts caught and dead toward caught total" do
    segment = { "locations" => %w[route_201 route_202 route_204], "gym" => "first_gym" }
    groups = {
      "route_201" => [ stub_group(status: "caught") ],
      "route_202" => [ stub_group(status: "dead") ]
    }
    assert_equal({ caught: 2, total: 3 }, segment_progress(segment, sample_locations, groups))
  end

  test "segment_progress returns zero/zero for an empty or non-catchable segment" do
    assert_equal({ caught: 0, total: 0 },
      segment_progress({ "locations" => [] }, sample_locations, {}))
    assert_equal({ caught: 0, total: 0 },
      segment_progress({ "locations" => %w[oreburgh_city] }, sample_locations, {}))
  end

  # ── segment_open_by_default? ──────────────────────────────────────────

  test "segment_open_by_default? matches the segment that contains the next-uncaught key" do
    seg0 = sample_progression["segments"][0]
    seg1 = sample_progression["segments"][1]
    assert segment_open_by_default?(seg0, "route_201")
    refute segment_open_by_default?(seg1, "route_201")
  end

  test "segment_open_by_default? returns false when next_uncaught_key is nil" do
    seg = sample_progression["segments"][0]
    refute segment_open_by_default?(seg, nil)
  end

  # ── node_status_class ─────────────────────────────────────────────────

  test "node_status_class returns special only for uncaught specials" do
    starter = sample_locations["starter"]
    assert_equal "special", node_status_class(starter, "uncaught")
    assert_equal "caught",  node_status_class(starter, "caught")
    assert_equal "dead",    node_status_class(starter, "dead")
  end

  test "node_status_class falls through to status for non-special types" do
    route = sample_locations["route_201"]
    assert_equal "caught",   node_status_class(route, "caught")
    assert_equal "uncaught", node_status_class(route, "uncaught")
  end

  # ── groups_json_for additive payload ──────────────────────────────────

  test "groups_json_for returns [] when groups is blank" do
    assert_equal "[]", groups_json_for(nil)
    assert_equal "[]", groups_json_for([], GREY)
  end

  test "groups_json_for emits per-group id + per-pokemon id/is_mine/level fields" do
    run = create(:soul_link_run)
    group = create(:soul_link_pokemon_group, soul_link_run: run, status: "caught", nickname: "TOMMY", location: "route_201")
    p_mine    = create(:soul_link_pokemon, soul_link_run: run, soul_link_pokemon_group: group,
                       discord_user_id: GREY, species: "Starly", name: "Starly",
                       location: "route_201", status: "caught", level: 12)
    p_other   = create(:soul_link_pokemon, soul_link_run: run, soul_link_pokemon_group: group,
                       discord_user_id: GREY + 1, species: "Bidoof", name: "Bidoof",
                       location: "route_201", status: "caught", level: 11)

    json = groups_json_for([ group ], GREY)
    parsed = JSON.parse(json)
    assert_equal 1, parsed.size

    g = parsed.first
    assert_equal group.id, g["id"]
    assert_equal "TOMMY",  g["nickname"]
    assert_equal "Starly", g["species_for_user"]

    pokes = g["pokemon"]
    assert_equal 2, pokes.size
    mine = pokes.find { |p| p["is_mine"] }
    assert_equal p_mine.id, mine["id"]
    assert_equal 12,        mine["level"]
    assert_equal "Starly",  mine["species"]

    other = pokes.find { |p| p["id"] == p_other.id }
    refute other["is_mine"]
  end

  # ── helpers ───────────────────────────────────────────────────────────

  private

  # `location_status` is the only thing we exercise on stubbed groups —
  # build_stubbed avoids a DB write per test for the YAML-driven
  # fixtures. The factory-derived `caught?` / `dead?` predicates use
  # `status` directly, so build_stubbed is sufficient.
  def stub_group(status:)
    build_stubbed(:soul_link_pokemon_group, status: status)
  end

  def sample_progression
    {
      "segments" => [
        { "locations" => %w[starter route_201 route_202 oreburgh_city], "gym" => "first_gym" },
        { "locations" => %w[route_204 eterna_city], "gym" => "second_gym" }
      ],
      "endpoint" => "Elite Four / Champion"
    }
  end

  def sample_locations
    {
      "starter"        => { "name" => "Starter Pokemon", "type" => "special" },
      "route_201"      => { "name" => "Route 201",       "type" => "route" },
      "route_202"      => { "name" => "Route 202",       "type" => "route" },
      "route_204"      => { "name" => "Route 204",       "type" => "route" },
      "oreburgh_city"  => { "name" => "Oreburgh City",   "type" => "city",   "gym_number" => 1 },
      "oreburgh_mine"  => { "name" => "Oreburgh Mine",   "type" => "dungeon" },
      "lake_verity"    => { "name" => "Lake Verity",     "type" => "lake" },
      "eterna_city"    => { "name" => "Eterna City",     "type" => "city",   "gym_number" => 2 }
    }
  end

  def sample_gym_info
    {
      "first_gym" => {
        "name" => "Oreburgh Gym", "max_level" => 14,
        "location" => "oreburgh_city", "number" => 1,
        "leader" => "Roark", "type" => "Rock"
      },
      "second_gym" => {
        "name" => "Eterna Gym", "max_level" => 22,
        "location" => "eterna_city", "number" => 2,
        "leader" => "Gardenia", "type" => "Grass"
      },
      "eighth_gym" => {
        "name" => "Sunyshore Gym", "max_level" => 50,
        "location" => "sunyshore_city", "number" => 8,
        "leader" => "Volkner", "type" => "Electric"
      }
    }
  end
end
