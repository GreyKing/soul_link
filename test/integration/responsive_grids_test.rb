require "test_helper"

# Step 20 — layout regression test for the gb-grid-N responsive cascade.
# Without a headless-browser driver in the unit-test runner, we assert the
# CSS file shape directly. Same idea as the YAML-data tests in
# test/services/soul_link/game_state_*_test.rb — read the source-of-truth
# file, parse, assert on the structure.
class ResponsiveGridsTest < ActiveSupport::TestCase
  CSS_PATH = Rails.root.join("app/assets/stylesheets/pixeldex.css")

  setup do
    @css = File.read(CSS_PATH)
  end

  test "the existing 900px breakpoint keeps gb-grid-3 and gb-grid-4 at 2 columns" do
    block = @css[/@media\s*\(max-width:\s*900px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block, "expected an `@media (max-width: 900px)` block"

    assert_match(/\.gb-grid-3\s*\{\s*grid-template-columns:\s*repeat\(2,\s*1fr\)/, block)
    assert_match(/\.gb-grid-4\s*\{\s*grid-template-columns:\s*repeat\(2,\s*1fr\)/, block)
  end

  test "the new 520px breakpoint collapses gb-grid-3 and gb-grid-4 to a single column" do
    block = @css[/@media\s*\(max-width:\s*520px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block, "expected an `@media (max-width: 520px)` block (Step 20)"

    assert_match(/\.gb-grid-3\s*\{\s*grid-template-columns:\s*1fr\s*[;}]/, block)
    assert_match(/\.gb-grid-4\s*\{\s*grid-template-columns:\s*1fr\s*[;}]/, block)
  end

  test "gb-grid-2 stays 2-column at every size (no override in either breakpoint)" do
    # gb-grid-2 is declared once at the top-level, never overridden in any
    # media query — that's the contract because 2-column with label/value
    # pairs reads fine on phones.
    breakpoint_900 = @css[/@media\s*\(max-width:\s*900px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m] || ""
    breakpoint_520 = @css[/@media\s*\(max-width:\s*520px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m] || ""

    assert_no_match(/\.gb-grid-2\s*\{/, breakpoint_900, "gb-grid-2 should not be overridden in the 900px breakpoint")
    assert_no_match(/\.gb-grid-2\s*\{/, breakpoint_520, "gb-grid-2 should not be overridden in the 520px breakpoint")
  end
end
