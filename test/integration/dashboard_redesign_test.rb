require "test_helper"

# Step 24 R1 — markup-assertion test for the redesigned dashboard.
# Same pattern as `pc_box_redesign_test.rb` (Step 22) and
# `map_redesign_test.rb` (Step 23): we cannot drive Stimulus
# interactively without a system-test driver, but we CAN verify
# that `/` ships the wiring locked in the brief — namespace,
# controllers, ARIA tablist, badge dots, sub-tab default-active,
# emulator-ROM buttons in the canonical RUNS surface, and
# `/runs → root_path(anchor: "runs")` redirect.
class DashboardRedesignTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    login_as(GREY)
  end

  # ── Wrapper + Stimulus controllers ────────────────────────────────────

  test "the .dash-r1 wrapper renders with the dashboard + pixeldex Stimulus controllers attached" do
    get root_path
    assert_response :success

    assert_match(/class="dash-r1"/, response.body)
    # Both controllers attached on the wrapper, in either order. The new
    # `run-management` is also there because the title-bar's
    # `+ START NEW RUN` reaches the controller via DOM bubbling.
    assert_match(/data-controller="[^"]*\bdashboard\b[^"]*"/, response.body)
    assert_match(/data-controller="[^"]*\bpixeldex\b[^"]*"/, response.body)
    assert_match(/data-controller="[^"]*\brun-management\b[^"]*"/, response.body)
  end

  # ── Title bar — run pill + stat strip ────────────────────────────────

  test "the title-bar renders with the run-pill replacing the legacy <select>" do
    get root_path
    assert_response :success

    # No more inline `onchange="window.location.href=..."` (audit annotation C).
    assert_no_match(/onchange="window\.location\.href/, response.body)

    # The run-pill button + its Stimulus controller are present.
    assert_match(/<button[^>]*class="run-pill"/, response.body)
    assert_match(/data-controller="run-picker"/, response.body)
    assert_match(/data-run-picker-target="trigger"/, response.body)
    assert_match(/aria-haspopup="listbox"/, response.body)
  end

  test "the title-bar stat-strip renders 4 inline items" do
    seed_for_stats
    get root_path
    assert_response :success

    # Stat strip exists and carries the four expected items.
    assert_match(/class="stat-strip"/, response.body)
    assert_match(/<div class="item">\s*<span>CAUGHT<\/span>\s*<span class="val">2<\/span>/m, response.body)
    assert_match(/<div class="item alive"><span>ALIVE<\/span>\s*<span class="val">1<\/span>/m, response.body)
    assert_match(/<div class="item dead"><span>DEAD<\/span>\s*<span class="val">1<\/span>/m, response.body)
    assert_match(/<div class="item badges"><span>BADGES<\/span>\s*<span class="val">0\/8<\/span>/m, response.body)
  end

  # ── Tab bar — real WAI-ARIA tablist ──────────────────────────────────

  test "the tab-bar renders with role=tablist, role=tab, aria-selected, and aria-controls on each tab" do
    get root_path
    assert_response :success

    assert_match(/<div class="tab-bar"\s+role="tablist"\s+aria-label="Dashboard sections"/, response.body)

    # Each of the seven dashboard tabs carries the expected ARIA wiring.
    %w[party pcbox map gyms strategy runs calc].each do |key|
      assert_match(/<button[^>]*role="tab"[^>]*id="tab-#{key}"[^>]*aria-controls="panel-#{key}"/m, response.body,
        "expected tab role+id+aria-controls for #{key}")
    end
  end

  test "the active tab has aria-selected=true and tabindex=0; others have aria-selected=false and tabindex=-1" do
    get root_path
    assert_response :success

    # Scope to the main dashboard tab-bar (the right rail also uses `role="tab"`).
    # The dashboard tab-bar is followed by the `.pc-layout` grid.
    tab_bar = response.body[%r{<div class="tab-bar".*?aria-label="Dashboard sections".*?(?=<div class="pc-layout")}m]
    refute_nil tab_bar, "expected to find the main .tab-bar block"

    # Exactly one main tab carries `aria-selected="true"` (PC BOX is default).
    selected_count = tab_bar.scan(/role="tab"[^>]*aria-selected="true"/).size
    assert_equal 1, selected_count, "expected exactly one main tab with aria-selected=true"

    # That tab has tabindex="0"; every other tab has tabindex="-1".
    assert_match(/role="tab"[^>]*id="tab-pcbox"[^>]*aria-selected="true"[^>]*tabindex="0"/m, response.body)

    # All inactive tabs share tabindex="-1".
    %w[party map gyms strategy runs calc].each do |key|
      assert_match(/id="tab-#{key}"[^>]*aria-selected="false"[^>]*tabindex="-1"/m, response.body,
        "expected inactive tab #{key} with tabindex=-1")
    end
  end

  # ── Live-update badge dots ───────────────────────────────────────────

  test "the PC BOX tab carries a badge-dot when auto-detected catches exist" do
    seed_auto_detected_catch
    get root_path
    assert_response :success

    # The badge-dot lives inside the PC BOX tab button.
    assert_match(
      %r{<button[^>]*id="tab-pcbox"[^>]*>.*?<span class="badge-dot"[^>]*></span>.*?</button>}m,
      response.body
    )
  end

  test "the PC BOX tab does NOT carry a badge-dot when no auto-detected catches exist" do
    get root_path
    assert_response :success

    pcbox_block = response.body[%r{<button[^>]*id="tab-pcbox"[^>]*>.*?</button>}m]
    refute_nil pcbox_block, "expected to find the PC BOX tab markup"
    refute_match(/<span class="badge-dot"/, pcbox_block,
      "PC BOX tab should not carry a badge-dot without auto-detected catches")
  end

  test "the GYMS tab carries a badge-dot when an active draft exists" do
    create(:gym_draft, soul_link_run: @run, status: "lobby")
    get root_path
    assert_response :success

    assert_match(
      %r{<button[^>]*id="tab-gyms"[^>]*>.*?<span class="badge-dot"[^>]*></span>.*?</button>}m,
      response.body
    )
  end

  # ── Right status rail ────────────────────────────────────────────────

  test "the right status rail renders with 3 sub-tabs (PARTY/GYMS/MAP)" do
    get root_path
    assert_response :success

    assert_match(/<aside class="status-rail"\s+data-controller="status-rail"/, response.body)
    rail_block = response.body[%r{<aside class="status-rail".*?</aside>}m]
    refute_nil rail_block, "expected to find the .status-rail wrapper"

    sub_tab_keys = rail_block.scan(/data-status-rail-tab-param="([^"]+)"/m).flatten
    assert_equal %w[party gyms map], sub_tab_keys
  end

  test "the GYMS sub-tab is the default-active one" do
    get root_path
    assert_response :success

    rail_block = response.body[%r{<aside class="status-rail".*?</aside>}m]
    refute_nil rail_block

    # Exactly one sub-tab carries `aria-selected="true"`. Attribute order
    # in the rendered ERB: aria-selected comes BEFORE data-status-rail-tab-param.
    selected = rail_block.scan(/aria-selected="true"[^>]*data-status-rail-tab-param="([^"]+)"/m).flatten
    assert_equal [ "gyms" ], selected
  end

  test "the GYMS sub-tab renders the START GYM DRAFT CTA when next_gym is present" do
    get root_path
    assert_response :success

    rail_block = response.body[%r{<aside class="status-rail".*?</aside>}m]
    refute_nil rail_block
    assert_match(/class="next-battle"/, rail_block)
    assert_match(/START GYM DRAFT/, rail_block)
  end

  test "the GYMS sub-tab does NOT render the START GYM DRAFT CTA in read-only mode (wiped run)" do
    @run.update_columns(wiped_at: Time.current)
    get root_path
    assert_response :success

    rail_block = response.body[%r{<aside class="status-rail".*?</aside>}m]
    refute_nil rail_block

    refute_match(/START GYM DRAFT/, rail_block)
    assert_match(/RUN ENDED/, rail_block)
  end

  test "the PARTY sub-tab renders one row per registered player" do
    get root_path
    assert_response :success

    party_panel = response.body[%r{<section[^>]*id="status-panel-party".*?</section>}m]
    refute_nil party_panel, "expected to find the PARTY sub-tab panel"

    expected_count = SoulLink::GameState.players.size
    actual_cards = party_panel.scan(/class="player-card[^"]*"/).size
    assert_equal expected_count, actual_cards
  end

  test "the current user's PARTY sub-tab row has the YOU pill and the amber border" do
    get root_path
    assert_response :success

    party_panel = response.body[%r{<section[^>]*id="status-panel-party".*?</section>}m]
    refute_nil party_panel

    # Exactly one card carries the `you` modifier class (current user).
    you_cards = party_panel.scan(/class="player-card you"/).size
    assert_equal 1, you_cards
    # And that card carries the YOU pill.
    assert_match(/class="player-card you">.*?<span class="you-pill">YOU<\/span>/m, party_panel)
  end

  # ── Step 24 RUNS-tab consolidation ───────────────────────────────────

  test "the RUNS tab includes the Generate Emulator ROMs button when status :none" do
    get root_path
    assert_response :success

    # The trigger is hand-written ERB (not via a Rails tag helper), so
    # the literal `>` survives without HTML-escape. `emulator_status`
    # defaults to `:none` for a run with no sessions, so the button is
    # visible (class lacks the `hidden` modifier).
    assert_match(/data-action="click->run-management#generateEmulatorRoms"/, response.body)
    assert_match(/Generate Emulator ROMs/, response.body)
    assert_match(
      %r{<button[^>]*data-action="click->run-management#generateEmulatorRoms"[^>]*class="gb-btn-primary gb-btn-sm "[^>]*>\s*Generate Emulator ROMs}m,
      response.body
    )
  end

  test "the RUNS tab includes the Regenerate ROMs button when status :failed" do
    # `emulator_status` is :failed when at least one session is failed.
    create(:soul_link_emulator_session, soul_link_run: @run, status: "failed")
    get root_path
    assert_response :success

    # The Regenerate button is visible (no `hidden` modifier) when status is :failed.
    # (Generate button DOES carry hidden, since :failed != :none.)
    assert_match(
      %r{<button[^>]*data-action="click->run-management#regenerateEmulatorRoms"[^>]*class="gb-btn-primary gb-btn-sm "[^>]*>\s*Regenerate ROMs}m,
      response.body
    )
  end

  test "the RUNS tab does NOT include the legacy /runs page selector" do
    get root_path
    assert_response :success

    # Sanity: the legacy `_run_sidebar_card`-style heading from the deleted
    # `runs/index.html.erb` is gone.
    refute_match(/RUN MANAGEMENT/i, response.body)
    # And the inline `gb-page-title` headline from that page is absent.
    refute_match(/class="gb-page-title">RUN MANAGEMENT/, response.body)
  end

  test "/runs redirects to root_path with #runs anchor" do
    get runs_path
    assert_includes [ 301, 302 ], response.status
    assert response.redirect_url.end_with?("#runs"),
      "expected redirect to end with #runs, got #{response.redirect_url.inspect}"
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  private

  def seed_for_stats
    g_caught = create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "ALIVE", location: "Route 201")
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: g_caught,
           discord_user_id: GREY, species: "Starly", name: "ALIVE", location: "Route 201", status: "caught")

    g_dead = create(:soul_link_pokemon_group, soul_link_run: @run, status: "dead", nickname: "FALLEN", location: "Route 202")
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: g_dead,
           discord_user_id: GREY, species: "Bidoof", name: "FALLEN", location: "Route 202", status: "dead")
  end

  def seed_auto_detected_catch
    create(:soul_link_pokemon,
           soul_link_run: @run, soul_link_pokemon_group: nil,
           discord_user_id: GREY, species: "Kricketot", name: "(unassigned)",
           location: "Route 204", status: "caught",
           pid: 0xAAAA_BBBB, level: 4, acquired_via: "catch", trade_in: false,
           caught_off_feed: false, caught_at: 2.minutes.ago)
  end
end
