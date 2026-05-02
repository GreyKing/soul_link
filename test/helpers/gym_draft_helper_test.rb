require "test_helper"

class GymDraftHelperTest < ActionView::TestCase
  GREY    = 153665622641737728
  ARATY   = 600802903967531093

  setup do
    @run = create(:soul_link_run)
  end

  test "player_avatar_image renders an <img> when the run has a cached avatar URL" do
    @run.update!(player_avatars: { GREY.to_s => "https://cdn.discord/test.png" })
    SoulLink::GameState.stub(:player_name, "Grey") do
      html = player_avatar_image(@run, GREY)
      assert_match(/<img/, html)
      assert_match(/src="https:\/\/cdn\.discord\/test\.png"/, html)
      assert_match(/alt="Grey"/, html)
      assert_match(/gb-avatar/, html)
      assert_match(/gb-avatar--32/, html)
    end
  end

  test "player_avatar_image falls back to an initial circle when no URL is cached" do
    SoulLink::GameState.stub(:player_name, "Araty") do
      html = player_avatar_image(@run, ARATY)
      assert_no_match(/<img/, html)
      assert_match(/gb-avatar--initial/, html)
      # First letter of the name, uppercased.
      assert_match(/>A<\/span>/, html)
    end
  end

  test "player_avatar_image fallback color is deterministic per discord_user_id" do
    # Same uid should always pick the same color slot — test calls the
    # helper twice and confirms the same `gb-avatar--cN` class.
    SoulLink::GameState.stub(:player_name, "Grey") do
      first = player_avatar_image(@run, GREY)
      second = player_avatar_image(@run, GREY)
      assert_equal first, second
      assert_match(/gb-avatar--c\d/, first)
    end
  end

  test "player_avatar_image handles a player_avatars JSON of nil" do
    @run.update!(player_avatars: nil)
    SoulLink::GameState.stub(:player_name, "Grey") do
      html = player_avatar_image(@run, GREY)
      assert_match(/gb-avatar--initial/, html)
    end
  end

  test "player_avatar_image accepts a custom size" do
    SoulLink::GameState.stub(:player_name, "Grey") do
      html = player_avatar_image(@run, GREY, size: 24)
      assert_match(/gb-avatar--24/, html)
    end
  end
end
