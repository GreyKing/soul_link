require "test_helper"

class EmulatorHelperTest < ActionView::TestCase
  # ── format_play_time ────────────────────────────────────────────────────

  test "format_play_time returns the em-dash placeholder for nil" do
    assert_equal "—", format_play_time(nil)
  end

  test "format_play_time formats zero seconds as 0h 0m" do
    assert_equal "0h 0m", format_play_time(0)
  end

  test "format_play_time formats sub-hour durations" do
    assert_equal "0h 1m", format_play_time(60)
    assert_equal "0h 30m", format_play_time(1_800)
  end

  test "format_play_time formats multi-hour durations" do
    assert_equal "1h 1m", format_play_time(3_660)
    assert_equal "12h 43m", format_play_time(45_780)
  end

  test "format_play_time clamps negative input to zero" do
    assert_equal "0h 0m", format_play_time(-100)
  end

  # ── format_map_name ─────────────────────────────────────────────────────

  test "format_map_name returns nil for nil input" do
    assert_nil format_map_name(nil)
  end

  test "format_map_name returns the canonical name when GameState knows the ID" do
    SoulLink::GameState.stub(:map_name, "Eterna City") do
      assert_equal "Eterna City", format_map_name(8)
    end
  end

  test "format_map_name returns Map #N fallback when GameState returns nil" do
    SoulLink::GameState.stub(:map_name, nil) do
      assert_equal "Map #99999", format_map_name(99999)
    end
  end

  test "format_map_name fallback works with small integer IDs" do
    SoulLink::GameState.stub(:map_name, nil) do
      assert_equal "Map #42", format_map_name(42)
    end
  end

  # ── format_progress_phrase ──────────────────────────────────────────────
  #
  # Step 21 R3 — locked rule: nil/<60 → "less than a minute"; 60..119 →
  # "1 minute" (singular); 120..3599 → "N minutes" (integer div);
  # 3600..7199 → "1 hour" (singular); ≥ 7200 → "N hours" (integer div,
  # truncating). Test bench pins the boundaries.

  test "format_progress_phrase returns less-than-a-minute for nil" do
    assert_equal "less than a minute of progress", format_progress_phrase(nil)
  end

  test "format_progress_phrase returns less-than-a-minute for sub-60-second values" do
    assert_equal "less than a minute of progress", format_progress_phrase(0)
    assert_equal "less than a minute of progress", format_progress_phrase(30)
    assert_equal "less than a minute of progress", format_progress_phrase(59)
  end

  test "format_progress_phrase returns singular '1 minute' at exactly 60 seconds" do
    assert_equal "1 minute of progress", format_progress_phrase(60)
  end

  test "format_progress_phrase returns plural minutes from 120s up" do
    assert_equal "2 minutes of progress", format_progress_phrase(120)
    assert_equal "30 minutes of progress", format_progress_phrase(1_800)
    assert_equal "59 minutes of progress", format_progress_phrase(3_540)
  end

  test "format_progress_phrase returns singular '1 hour' at exactly 3600 seconds" do
    assert_equal "1 hour of progress", format_progress_phrase(3_600)
  end

  test "format_progress_phrase returns singular '1 hour' through 7199 seconds (1h59m)" do
    assert_equal "1 hour of progress", format_progress_phrase(7_199)
  end

  test "format_progress_phrase returns plural hours from 7200s (2h) up" do
    assert_equal "2 hours of progress", format_progress_phrase(7_200)
    assert_equal "4 hours of progress", format_progress_phrase(4 * 3600 + 23 * 60)
    assert_equal "12 hours of progress", format_progress_phrase(45_780)
  end

  test "format_progress_phrase truncates partial hours (3h59m → 3 hours)" do
    assert_equal "3 hours of progress", format_progress_phrase(3 * 3600 + 59 * 60)
  end
end
