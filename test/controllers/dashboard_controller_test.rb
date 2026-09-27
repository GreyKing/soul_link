require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  test "shows the latest run with the no-run panel when the guild has no active run" do
    create(:soul_link_run, active: false)
    latest = create(:soul_link_run, active: false)
    login_as(GREY)

    get root_path

    assert_response :success
    assert_select "[data-run-management-target=noRunPanel]:not(.hidden)"
    assert_select "a[href='/?run_id=#{latest.id}']", text: /VIEWING/
  end

  test "an unknown run_id falls back to a run instead of redirecting to login" do
    create(:soul_link_run)
    login_as(GREY)

    get root_path(run_id: 0)

    assert_response :success
  end

  test "renders the no-runs page when the guild has no runs at all" do
    run = create(:soul_link_run)
    login_as(GREY)
    run.destroy!

    get root_path

    assert_response :success
    assert_match "No runs yet", response.body
  end

  test "pages that need an active run send a logged-in user to the dashboard" do
    create(:soul_link_run, active: false)
    login_as(GREY)

    [ team_path, teams_path, map_path, gym_ready_path, species_path, gym_poll_path ].each do |path|
      get path
      assert_redirected_to root_path, "GET #{path}"
    end

    post gym_drafts_path
    assert_redirected_to root_path, "POST #{gym_drafts_path}"
  end

  test "the login page chain ends on the dashboard, not back at login" do
    create(:soul_link_run, active: false)
    login_as(GREY)

    get login_path
    assert_redirected_to team_path
    follow_redirect!
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
  end
end
