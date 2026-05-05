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

  # ── Step 21 R3 — design-token + scoped-rule assertions ──────────────────

  test "Step 21 R3 declares the three new tokens (--d0, --green-glow, --crimson) exactly once each in :root" do
    assert_equal 1, @css.scan(/--d0:\s*#0a1a0a/).size, "expected --d0 declared exactly once"
    assert_equal 1, @css.scan(/--green-glow:\s*#5fd45f/).size, "expected --green-glow declared exactly once"
    assert_equal 1, @css.scan(/--crimson:\s*#c75a5a/).size, "expected --crimson declared exactly once"
  end

  test "Step 21 R3 styles do NOT collapse .slot or .roster-card content inside the 520px breakpoint" do
    block = @css[/@media\s*\(max-width:\s*520px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block, "expected an `@media (max-width: 520px)` block"
    # Mobile breakpoint must not redefine the slot or roster-card layout
    # in a way that hides the body. Any `display: none` or
    # grid-template-columns override on these selectors would break the
    # mockup's mobile reflow contract (Screen 5 of the mockup).
    assert_no_match(/\.slot\s*\{[^}]*display:\s*none/m, block)
    assert_no_match(/\.roster-card\s*\{[^}]*display:\s*none/m, block)
  end

  test "Step 21 R3 styles do NOT collapse .slot or .roster-card content inside the 900px breakpoint" do
    block = @css[/@media\s*\(max-width:\s*900px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block, "expected an `@media (max-width: 900px)` block"
    assert_no_match(/\.slot\s*\{[^}]*display:\s*none/m, block)
    assert_no_match(/\.roster-card\s*\{[^}]*display:\s*none/m, block)
  end

  # ── Step 22 R2 — namespace + responsive contract for PC BOX redesign ──

  test "Step 22 R2 declares the .pc-box-r2 namespace at least once outside any media block" do
    css_no_media = @css.gsub(/@media[^{]*\{(?:[^{}]|\{[^{}]*\})*\}/m, "")
    assert_match(/\.pc-box-r2\s/, css_no_media,
      "expected .pc-box-r2 namespaced selectors declared outside any media block")
  end

  test "Step 22 R2 reflows the box grid to 3 columns inside the 520px breakpoint" do
    block = @css[/@media\s*\(max-width:\s*520px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block, "expected an `@media (max-width: 520px)` block (Step 20)"

    assert_match(/\.pc-box-r2\s+\.box-grid\s*\{[^}]*grid-template-columns:\s*repeat\(3,\s*1fr\)/, block)
  end

  test "Step 22 R2 stacks the type-coverage rail under the grid inside the 900px breakpoint" do
    block = @css[/@media\s*\(max-width:\s*900px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block, "expected an `@media (max-width: 900px)` block"

    assert_match(/\.pc-box-r2\s+\.box-layout\s*\{\s*grid-template-columns:\s*1fr\s*[;}]/, block)
  end

  test "Step 22 R2 styles do NOT collapse .pc-box-r2 cells or rows inside either breakpoint" do
    %w[520px 900px].each do |bp|
      block = @css[/@media\s*\(max-width:\s*#{bp}\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
      refute_nil block, "expected an `@media (max-width: #{bp})` block"
      # Same shape as the Step 21 contract for `.slot` / `.roster-card`.
      assert_no_match(/\.pc-box-r2\s+\.box-cell\s*\{[^}]*display:\s*none/m, block,
        "the #{bp} breakpoint must not hide .pc-box-r2 .box-cell")
      assert_no_match(/\.pc-box-r2\s+\.review-row\s*\{[^}]*display:\s*none/m, block,
        "the #{bp} breakpoint must not hide .pc-box-r2 .review-row")
    end
  end

  test "emulator-grid stays single-column outside any media block AND three-column at 900px" do
    # Single-column default (outside any @media). Strip every @media
    # block before searching so we only match the top-level rule.
    css_no_media = @css.gsub(/@media[^{]*\{(?:[^{}]|\{[^{}]*\})*\}/m, "")
    assert_match(
      /\.emulator-grid\s*\{[^}]*grid-template-columns:\s*1fr;/m,
      css_no_media,
      "expected .emulator-grid declared single-column outside any media block"
    )

    block_900 = @css[/@media\s*\(min-width:\s*900px\)\s*\{(?:[^{}]|\{[^{}]*\})*\}/m]
    refute_nil block_900, "expected an `@media (min-width: 900px)` block"
    assert_match(
      /\.emulator-grid\s*\{\s*grid-template-columns:\s*280px\s+minmax\(0,\s*1fr\)\s+280px;/m,
      block_900,
      "expected .emulator-grid three-column rule at the 900px breakpoint"
    )
  end
end
