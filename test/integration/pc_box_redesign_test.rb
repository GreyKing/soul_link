require "test_helper"

# Step 22 R2 — markup-assertion test for the new PC BOX dashboard tab.
# Same pattern as confirm_modal_flow_test: we can't drive Stimulus
# interactively without a system-test driver, but we CAN verify the rendered
# markup carries the wiring the brief locks down (data-controller, target
# attributes, action chains, filter chip params, etc.).
class PcBoxRedesignTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    login_as(GREY)
  end

  # ── Default state: review tray + unified grid ─────────────────────────

  test "renders the .pc-box-r2 wrapper with both Stimulus controllers attached" do
    seed_grid_groups
    get root_path
    assert_response :success

    assert_match(/class="pc-box-r2"/, response.body)
    # Both controllers attached, in either order.
    assert_match(/data-controller="(?:[^"]*\bpc-box-filter\b[^"]*\breview-tray\b|[^"]*\breview-tray\b[^"]*\bpc-box-filter\b)/, response.body)
  end

  test "renders the REVIEW PARSED CATCHES tray with badge legend and per-row buttons" do
    seed_grid_groups
    seed_auto_catches
    get root_path
    assert_response :success

    assert_match(/class="review-tray"/, response.body)
    assert_match(/<h3>REVIEW PARSED CATCHES<\/h3>/, response.body)

    # All four legend rows present.
    assert_match(/class="badge-legend"/, response.body)
    assert_match(/<span class="badge first">1ST<\/span>/, response.body)
    assert_match(/<span class="badge trade">TRADE-IN<\/span>/, response.body)
    assert_match(/<span class="badge event">EVENT<\/span>/, response.body)
    assert_match(/<span class="badge offfeed">OFF-FEED<\/span>/, response.body)

    # The first-encounter row gets the .first highlight + a primary LOG button.
    assert_match(/class="review-row first"/, response.body)
    assert_match(/class="primary"[^>]*data-action="click->dashboard#openCatchModal click->review-tray#prefillCatch"[^>]*>\s*LOG CATCH/m, response.body)

    # The trade-in row's SKIP gets the .primary class.
    assert_match(/<button[^>]*type="button"\s+class="primary"\s+data-action="click->review-tray#dismiss">\s*SKIP/m, response.body)

    # Each row has a SKIP button wired to review-tray#dismiss.
    skip_count = response.body.scan(/data-action="click->review-tray#dismiss"/).size
    assert_equal 2, skip_count, "expected one SKIP button per review row"
  end

  test "renders the four filter chips with correct counts" do
    seed_grid_groups
    get root_path
    assert_response :success

    # Buttons span multiple lines and contain `data-action="click->..."`
    # whose `>` would terminate `[^>]*` matchers — match each chip block
    # explicitly via .*? with the m flag.
    assert_match(/data-pc-box-filter-status-param="all".*?ALL · 3/m, response.body)
    assert_match(/data-pc-box-filter-status-param="team".*?ON TEAM · 1/m, response.body)
    assert_match(/data-pc-box-filter-status-param="storage".*?STORAGE · 1/m, response.body)
    assert_match(/data-pc-box-filter-status-param="fallen".*?FALLEN · 1/m, response.body)

    # Exactly one chip starts in the active state (ALL).
    assert_equal 1, response.body.scan(/class="filter-chip active"/).size

    assert_match(/data-pc-box-filter-target="searchInput"/, response.body)
  end

  test "renders the unified grid with one cell per status, each carrying data-status" do
    seed_grid_groups
    get root_path
    assert_response :success

    # Three cells in the .pc-box-r2 grid (we don't dig into ordering, just count).
    cells = response.body.scan(/data-pc-box-filter-target="cell"[^>]*data-status="([^"]+)"/m).flatten
    assert_includes cells, "team"
    assert_includes cells, "storage"
    assert_includes cells, "fallen"
    assert_equal 3, cells.size

    # Cells preserve the existing pixeldex#selectPokemon click action.
    assert_match(/class="box-cell team"[^>]*data-action="click->pixeldex#selectPokemon"/m, response.body)
  end

  test "renders the type-coverage rail" do
    seed_grid_groups
    get root_path
    assert_response :success

    assert_match(/<aside class="type-coverage" data-pc-box-filter-target="rail">/, response.body)
    assert_match(/<h3>TYPE COVERAGE<\/h3>/, response.body)
  end

  # ── Empty state ───────────────────────────────────────────────────────

  test "renders the empty-tray bar and ALL CAUGHT-UP status when no auto-catches exist" do
    seed_grid_groups
    # No auto-catches seeded.
    get root_path
    assert_response :success

    assert_match(/class="empty-tray-bar"/, response.body)
    assert_match(/No new parsed catches to review/, response.body)
    assert_match(/ALL CAUGHT-UP/, response.body)
    refute_match(/<h3>REVIEW PARSED CATCHES<\/h3>/, response.body)
  end

  # ── Read-only mode ────────────────────────────────────────────────────

  test "read-only mode hides + NEW CATCH and per-row LOG/EDIT but keeps SKIP" do
    seed_grid_groups
    seed_auto_catches
    @run.update_columns(wiped_at: Time.current)
    get root_path
    assert_response :success

    refute_match(/\+ NEW CATCH/, response.body)
    refute_match(/data-action="click->dashboard#openCatchModal click->review-tray#prefillCatch"/, response.body)
    # SKIP is still wired (client-only, no backend impact).
    assert_match(/data-action="click->review-tray#dismiss"/, response.body)
  end

  private

  # Seeds one team-group, one storage-group, one fallen-group for the GREY user.
  def seed_grid_groups
    team_group = create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "TEAMMATE", location: "Route 201")
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: team_group,
           discord_user_id: GREY, species: "Starly", name: "TEAMMATE", location: "Route 201", status: "caught")

    storage_group = create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "BENCHIE", location: "Route 202")
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: storage_group,
           discord_user_id: GREY, species: "Bidoof", name: "BENCHIE", location: "Route 202", status: "caught")

    fallen_group = create(:soul_link_pokemon_group, soul_link_run: @run, status: "dead", nickname: "FALLEN", location: "Route 203")
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: fallen_group,
           discord_user_id: GREY, species: "Shinx", name: "FALLEN", location: "Route 203", status: "dead")

    # Put TEAMMATE on the team so it shows up under @on_team_groups.
    team = create(:soul_link_team, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_team_slot, :slot_1, soul_link_team: team, soul_link_pokemon_group: team_group)
  end

  # Seeds two auto-detected catches: one first-encounter (recommends LOG)
  # and one trade-in (recommends SKIP).
  def seed_auto_catches
    create(:soul_link_pokemon,
           soul_link_run: @run, soul_link_pokemon_group: nil,
           discord_user_id: GREY, species: "Kricketot", name: "(unassigned)",
           location: "Route 204", status: "caught",
           pid: 0xAAAA_BBBB, level: 4, acquired_via: "catch", trade_in: false,
           caught_off_feed: false, caught_at: 2.minutes.ago)

    create(:soul_link_pokemon,
           soul_link_run: @run, soul_link_pokemon_group: nil,
           discord_user_id: GREY, species: "Machop", name: "(unassigned)",
           location: "Eterna City", status: "caught",
           pid: 0xCCCC_DDDD, level: 12, acquired_via: "catch", trade_in: true,
           caught_off_feed: false, caught_at: 1.minute.ago)
  end
end
