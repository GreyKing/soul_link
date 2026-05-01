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
end
