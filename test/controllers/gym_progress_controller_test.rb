require "test_helper"

class GymProgressControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
  end

  test "update requires login" do
    patch gym_progress_path(gym_number: 1)
    assert_redirected_to login_path
  end

  test "mark gym beaten creates result and increments gyms_defeated" do
    login_as(GREY)

    patch gym_progress_path(gym_number: 1)
    assert_redirected_to root_path(anchor: "gyms")
    assert_equal "Gym 1 marked beaten.", flash[:notice]
    assert_equal 1, @run.reload.gyms_defeated
    assert @run.gym_results.exists?(gym_number: 1)
  end

  test "unmark beaten destroys result and decrements gyms_defeated" do
    login_as(GREY)
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current)
    @run.update!(gyms_defeated: 1)

    patch gym_progress_path(gym_number: 1)
    assert_redirected_to root_path(anchor: "gyms")
    assert_equal "Gym 1 unmarked.", flash[:notice]
    assert_equal 0, @run.reload.gyms_defeated
    assert_not @run.gym_results.exists?(gym_number: 1)
  end

  test "unmark non-highest gym is rejected" do
    login_as(GREY)
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current)
    @run.gym_results.create!(gym_number: 2, beaten_at: Time.current)
    @run.update!(gyms_defeated: 2)

    patch gym_progress_path(gym_number: 1)
    assert_redirected_to root_path(anchor: "gyms")
    assert_equal "Can only unmark the most recent gym", flash[:alert]
    assert_equal 2, @run.reload.gyms_defeated
    assert @run.gym_results.exists?(gym_number: 1)
  end

  test "invalid gym number is rejected" do
    login_as(GREY)

    patch gym_progress_path(gym_number: 99)
    assert_redirected_to root_path(anchor: "gyms")
    assert_equal "Invalid gym number", flash[:alert]
  end

  test "JSON request returns gyms_defeated count without redirect" do
    login_as(GREY)

    patch gym_progress_path(gym_number: 1), as: :json
    assert_response :success
    assert_equal({ "gyms_defeated" => 1 }, response.parsed_body)
    assert_equal 1, @run.reload.gyms_defeated
  end
end
