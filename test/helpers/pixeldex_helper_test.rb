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
end
