require "test_helper"

class DesignCanonTest < ActionDispatch::IntegrationTest
  CSS_PATH = Rails.root.join("app", "assets", "stylesheets", "pixeldex.css")
  CANON_PATH = Rails.root.join("app", "assets", "stylesheets", "design_canon.md")

  test "pixeldex.css declares the canonical accent token" do
    css = CSS_PATH.read
    assert_match(/--accent:\s*var\(--green-glow\)/, css,
                 "Step 26: --accent rebased to --green-glow")
  end

  test "pixeldex.css declares the danger-family tokens" do
    css = CSS_PATH.read
    assert_match(/--danger-bg:\s*#4a1c1c/, css)
    assert_match(/--danger-border:\s*#6b2c2c/, css)
    assert_match(/--danger-fg:\s*#e8a0a0/, css)
  end

  test "pixeldex.css declares the spacing scale" do
    css = CSS_PATH.read
    %w[--s-1 --s-2 --s-3 --s-4 --s-5 --s-6 --s-7 --s-8].each do |tok|
      assert_match(/#{Regexp.escape(tok)}:\s*\d+px/, css,
                   "Step 25 canon: spacing token #{tok} missing from :root")
    end
  end

  test "danger family tokens replaced legacy hardcoded hexes on shared surfaces" do
    css = CSS_PATH.read
    # gb-flash-alert / gb-btn-danger / gb-status-dead must reference the danger tokens
    %w[.gb-flash-alert .gb-btn-danger .gb-status-dead].each do |sel|
      block = css[/#{Regexp.escape(sel)}\s*\{[^}]+\}/m]
      assert block, "missing block for #{sel}"
      assert_match(/var\(--danger-/, block,
                   "Step 25 canon: #{sel} must use var(--danger-*) tokens")
    end
  end

  test "design_canon.md exists and references the locked tokens" do
    assert CANON_PATH.exist?, "design_canon.md must exist as the source of truth"
    md = CANON_PATH.read
    assert_match(/--accent/, md)
    assert_match(/--success/, md)
    assert_match(/--danger/, md)
  end
end
