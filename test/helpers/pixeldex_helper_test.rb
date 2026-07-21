require "test_helper"

# Step 22 R2 — unit tests for the new `recommended_review_action` helper.
# Pure-function, badge-driven decision: event_gift / trade_in → :skip,
# otherwise :log. Used by the PC BOX REVIEW PARSED CATCHES tray to highlight
# the recommended primary action per row.
class PixeldexHelperTest < ActionView::TestCase
  include PixeldexHelper

  test "event_gift rows recommend SKIP" do
    pokemon = build_stubbed(:soul_link_pokemon, acquired_via: "event_gift", trade_in: false)
    assert_equal :skip, recommended_review_action(pokemon)
  end

  test "trade_in rows recommend SKIP" do
    pokemon = build_stubbed(:soul_link_pokemon, acquired_via: "catch", trade_in: true)
    assert_equal :skip, recommended_review_action(pokemon)
  end

  test "ordinary catches recommend LOG" do
    pokemon = build_stubbed(:soul_link_pokemon, acquired_via: "catch", trade_in: false)
    assert_equal :log, recommended_review_action(pokemon)
  end

  test "event_gift takes precedence over trade_in" do
    pokemon = build_stubbed(:soul_link_pokemon, acquired_via: "event_gift", trade_in: true)
    assert_equal :skip, recommended_review_action(pokemon)
  end

  # Step 30 — pixeldex_team_dialog is the roster-derived readiness line
  # rendered in the dashboard NEXT BATTLE panel and the PARTY surfaces.
  # Locks the four observable output forms.
  test "pixeldex_team_dialog returns the empty-team copy when team_size is 0" do
    assert_equal "No team built yet. Visit the Team page!",
                 pixeldex_team_dialog({ balance_notes: [], offensive_gaps: [] }, 0)
  end

  test "pixeldex_team_dialog returns the first balance-note warning when warnings are present" do
    type_analysis = {
      balance_notes: [
        { level: :warning, message: "Multiple team members weak to GROUND" },
        { level: :info, message: "Good type balance!" }
      ],
      offensive_gaps: []
    }
    assert_equal "Multiple team members weak to GROUND",
                 pixeldex_team_dialog(type_analysis, 4)
  end

  test "pixeldex_team_dialog returns the full-strength copy when there are no gaps and no warnings" do
    type_analysis = {
      balance_notes: [ { level: :info, message: "Good type balance!" } ],
      offensive_gaps: []
    }
    assert_equal "Team is at full strength! Full type coverage achieved.",
                 pixeldex_team_dialog(type_analysis, 4)
  end

  test "pixeldex_team_dialog returns the watch-out-for-types copy when gaps exist with no warnings" do
    type_analysis = {
      balance_notes: [],
      offensive_gaps: [ "Ice", "Fighting", "Dragon" ]
    }
    assert_equal "Team is solid. Watch out for ICE and FGT types.",
                 pixeldex_team_dialog(type_analysis, 4)
  end

  test "ability_effect_short returns the blurb for a known ability" do
    assert_equal "Immune to Ground", ability_effect_short("Levitate")
  end

  test "ability_effect_short returns empty string for an unknown ability" do
    assert_equal "", ability_effect_short("Not An Ability")
  end

  test "ability_effect_full returns the full text for a known ability" do
    assert_equal "Contact with this Pokémon may leave the attacker paralyzed.", ability_effect_full("Static")
  end

  test "ability_effect_full returns empty string for an unknown ability" do
    assert_equal "", ability_effect_full("Not An Ability")
  end
end
