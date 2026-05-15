require "test_helper"

class GymPollsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @run = create(:soul_link_run, :with_schedule_template, guild_id: LoginHelper::GUILD_ID)
    @player_id = 153665622641737728  # from config/soul_link/settings.yml — Grey
    login_as(@player_id)
  end

  test "GET /gym_poll without an active poll renders empty state" do
    get gym_poll_path
    assert_response :success
    assert_select "[data-empty-state]"
  end

  test "POST /gym_poll creates a poll from the template" do
    assert_difference -> { GymPoll.count }, 1 do
      post gym_poll_path
    end
    assert_redirected_to gym_poll_path
    poll = GymPoll.last
    assert_equal "open", poll.status
    assert_equal 3, poll.slots.length
  end

  test "POST /gym_poll refuses when run has no template" do
    @run.update!(schedule_template: nil)
    assert_no_difference -> { GymPoll.count } do
      post gym_poll_path
    end
    assert_response :unprocessable_entity
    assert_match(/schedule/i, response.body)
  end

  test "POST /gym_poll refuses when an open poll already exists" do
    create(:gym_poll, soul_link_run: @run)
    assert_no_difference -> { GymPoll.count } do
      post gym_poll_path
    end
    assert_response :conflict
  end

  test "DELETE /gym_poll destroys the active poll (reset)" do
    create(:gym_poll, soul_link_run: @run)
    assert_difference -> { GymPoll.count }, -1 do
      delete gym_poll_path
    end
    assert_redirected_to gym_poll_path
  end

  test "DELETE /gym_poll with no active poll is a no-op redirect" do
    assert_no_difference -> { GymPoll.count } do
      delete gym_poll_path
    end
    assert_redirected_to gym_poll_path
  end
end
