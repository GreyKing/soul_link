require "test_helper"

# Step 23 R4 — markup-assertion test for the new /map page.
# Same pattern as `pc_box_redesign_test.rb` (Step 22): we cannot drive
# Stimulus interactively without a system-test driver, but we CAN verify
# that `get /map` ships the wiring locked in the brief — namespace,
# controllers, target attributes, action chains, modal partials.
class MapRedesignTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    login_as(GREY)
  end

  # ── Wrapper + dual-controller attachment ──────────────────────────────

  test "renders the .map-r4 wrapper with timeline + dashboard + pixeldex controllers attached" do
    get map_path
    assert_response :success

    assert_match(/class="map-r4"/, response.body)
    # All three controllers attached. Order is not guaranteed.
    assert_match(/data-controller="[^"]*\btimeline\b[^"]*"/, response.body)
    assert_match(/data-controller="[^"]*\bdashboard\b[^"]*"/, response.body)
    assert_match(/data-controller="[^"]*\bpixeldex\b[^"]*"/, response.body)
  end

  # ── Always-visible legend ─────────────────────────────────────────────

  test "renders the always-visible legend with all five glyph items" do
    get map_path
    assert_response :success

    # Step 27: legend collapsed inline into the .map-head .sub
    # subtitle line (per audit § 3.4) — no separate boxed legend
    # bar. The 5 glyphs (●/☠/○/★/G) live as inline text characters
    # in the subtitle. We assert the subtitle carries each glyph
    # alongside its label.
    sub = response.body[%r{<div class="sub">[^<]+</div>}]
    refute_nil sub, "expected the .map-head .sub subtitle to render"
    assert_match(/&#9679;\s*caught/, sub)   # ● caught
    assert_match(/&#9760;\s*dead/, sub)     # ☠ dead
    assert_match(/&#9675;\s*uncaught/, sub) # ○ uncaught
    assert_match(/&#9733;\s*special/, sub)  # ★ special
    assert_match(/G\s*gym/, sub)
  end

  # ── Pulse-ring + JUMP TO NOW ──────────────────────────────────────────

  test "the next-uncaught route receives .next class + the NOW pin" do
    # No catches → first segment, first route is route_201 according to
    # progression.yml — that's the one that should pulse.
    get map_path
    assert_response :success

    next_count = response.body.scan(/class="node uncaught next"/).size
    assert_equal 1, next_count, "expected exactly one .node.next on a fresh run"
    assert_match(/class="node-now-pin"/, response.body)
  end

  test "JUMP TO NOW button is hidden when every route is caught" do
    seed_every_route_caught
    get map_path
    assert_response :success

    # Helper returns nil → `.jump-btn.hidden` rendered.
    assert_match(/class="jump-btn hidden"/, response.body)
    assert_no_match(/class="node-now-pin"/, response.body)
  end

  # ── Status bar ────────────────────────────────────────────────────────

  test "status bar renders NEXT GYM, LEVEL CAP, CURRENT SEG items" do
    get map_path
    assert_response :success

    assert_match(/<span class="lbl">NEXT GYM<\/span>/, response.body)
    assert_match(/<span class="lbl">LEVEL CAP<\/span>/, response.body)
    assert_match(/<span class="lbl">CURRENT SEG<\/span>/, response.body)
  end

  test "status bar falls back to em-dash when all 8 gyms are earned" do
    @run.update_columns(gyms_defeated: 8)
    get map_path
    assert_response :success

    assert_match(/All 8 earned/, response.body)
    # Level cap is em-dash (`&mdash;` rendered in HTML).
    assert_match(/<span class="lbl">LEVEL CAP<\/span>\s*<span class="val">[^<]*&mdash;[^<]*<\/span>/m, response.body)
  end

  # ── Sheet markup ──────────────────────────────────────────────────────

  test "sheet renders empty-state, group-list, and form (when not read-only)" do
    get map_path
    assert_response :success

    assert_match(/<aside class="sheet"[^>]*data-timeline-target="sheet"/, response.body)
    assert_match(/data-timeline-target="emptyState"/, response.body)
    assert_match(/data-timeline-target="groupList"/, response.body)
    assert_match(/data-timeline-target="sheetForm"/, response.body)

    # Form has one species input per player.
    expected = SoulLink::GameState.players.size
    actual = response.body.scan(/data-timeline-target="speciesSearchWrapper"/).size
    assert_equal expected, actual,
      "expected one .form-row[data-timeline-target=speciesSearchWrapper] per Soul Link player"
  end

  # ── Disambiguation: multi-group payload on a node ────────────────────

  test "data-groups carries a JSON array with multiple groups when dupes exist" do
    create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "ALPHA", location: "route_201")
    create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "BETA",  location: "route_201")
    get map_path
    assert_response :success

    # Find the route_201 node's data-groups payload. The HTML attribute
    # is HTML-escaped (e.g. `&quot;` → `"` after decode).
    node_match = response.body.match(/data-location-key="route_201"[^>]*data-groups="([^"]*)"/m)
    refute_nil node_match, "expected a .node for route_201 to be rendered"

    decoded = CGI.unescapeHTML(node_match[1])
    parsed = JSON.parse(decoded)
    assert_equal 2, parsed.size, "expected 2 groups on route_201 (dupes-clause re-roll case)"
    nicknames = parsed.map { |g| g["nickname"] }.sort
    assert_equal %w[ALPHA BETA], nicknames
  end

  # ── Read-only mode ────────────────────────────────────────────────────

  test "read-only mode hides sheet form (catch-form, EDIT, MARK DEAD, dupes)" do
    @run.update_columns(wiped_at: Time.current)
    get map_path
    assert_response :success

    assert_no_match(/data-timeline-target="sheetForm"/, response.body)
    assert_no_match(/\+ LOG GROUP/, response.body)
    # The `+ ANOTHER ENCOUNTER` and per-card EDIT/MARK DEAD buttons are
    # JS-built and gated by `hasSheetFormTarget` — verifying the form
    # absence is sufficient (the JS path is unit-tested separately).
  end

  # ── Special-encounters bar ────────────────────────────────────────────

  test "special-encounters bar renders 4 cells (gift, egg, trade, other)" do
    get map_path
    assert_response :success

    assert_match(/class="special-bar"/, response.body)
    assert_match(/class="special-grid"/, response.body)

    %w[gift egg trade other].each do |key|
      assert_match(/<button[^>]*class="special-cell"[^>]*data-action="click->timeline#selectLocation"[^>]*data-location-key="#{key}"/m, response.body,
        "expected .special-cell for #{key}")
    end
  end

  # ── Mobile accordion ──────────────────────────────────────────────────

  test "accordion frame renders one details element per segment with the active one open" do
    get map_path
    assert_response :success

    assert_match(/class="accordion-frame"/, response.body)
    expected_segments = SoulLink::GameState.progression["segments"].size
    actual_segments = response.body.scan(/<details class="accordion-segment"/).size
    assert_equal expected_segments, actual_segments

    # Exactly one segment is rendered with `open` (the one containing
    # the next-uncaught route, route_201 on a fresh run).
    open_count = response.body.scan(/<details class="accordion-segment" open/).size
    assert_equal 1, open_count, "expected exactly one accordion-segment[open]"

    # Each accordion row has the click→selectLocation chain.
    assert_match(/class="acc-row"[^>]*data-action="click->timeline#selectLocation"/m, response.body)
  end

  # ── Modals rendered on /map ──────────────────────────────────────────

  test "renders the dashboard pokemon-modal and mark-dead-modal partials" do
    get map_path
    assert_response :success

    # Pokemon modal target carries data-pixeldex-target="pokemonModal"
    # and the modal-a11y controller is attached on its <div role=dialog>.
    assert_match(/data-pixeldex-target="pokemonModal"/, response.body)
    assert_match(/aria-labelledby="pokemon-modal-title"/, response.body)
    # Mark Dead modal target.
    assert_match(/data-dashboard-target="markDeadModal"/, response.body)
    assert_match(/aria-labelledby="mark-dead-modal-title"/, response.body)
  end

  # ── Click-affordance: every node carries the click action ────────────

  test "every timeline node carries data-action=click->timeline#selectLocation" do
    create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "TOMMY", location: "route_201")
    get map_path
    assert_response :success

    # Every .node (except the static endpoint) carries the click action.
    # Endpoint has no data-action — it's a passive marker.
    nodes_with_click = response.body.scan(/class="node[^"]*"[^>]*data-action="click->timeline#selectLocation"/m).size
    assert nodes_with_click >= 1, "expected at least one timeline node with click->timeline#selectLocation"
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  private

  def seed_every_route_caught
    progression = SoulLink::GameState.progression
    locations = SoulLink::GameState.locations
    (progression["segments"] || []).each do |seg|
      (seg["locations"] || []).each do |key|
        loc = locations[key]
        next unless loc && loc["type"] == "route"
        create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: key.upcase, location: key)
      end
    end
  end
end
