require "test_helper"

class GymReadyControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    @groups = %i[route201 route202].map { |t| create(:soul_link_pokemon_group, t, soul_link_run: @run) }
    create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: @groups[0])
    create(:soul_link_pokemon, :route202_grey, soul_link_run: @run, soul_link_pokemon_group: @groups[1])
    # Personal team holds only ROY; the draft will hold TOMMY.
    @run.soul_link_teams.create!(discord_user_id: GREY).replace_slots!([ @groups[0].id ])
  end

  def complete_draft(groups)
    create(:gym_draft, soul_link_run: @run, status: "complete",
      state_data: { "ready_players" => [], "first_pick_votes" => {},
                    "picks" => groups.each_with_index.map { |g, i| { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY } } })
  end

  test "shows the personal team when no completed draft is pending" do
    login_as(GREY)
    get gym_ready_path
    assert_response :success
    assert_select "#gym-ready-team[data-team-source=personal]"
    assert_select "#gym-ready-team", text: /Starly/
    assert_select "#gym-ready-team", text: /Budew/, count: 0
  end

  test "shows the drafted team when a completed draft is pending" do
    complete_draft([ @groups[1] ])
    login_as(GREY)
    get gym_ready_path
    assert_response :success
    assert_select "#gym-ready-team[data-team-source=draft]"
    assert_select "#gym-ready-team", text: /DRAFTED TEAM/
    assert_select "#gym-ready-team", text: /Budew/
    assert_select "#gym-ready-team", text: /Starly/, count: 0
  end

  test "falls back to the personal team once the draft has been used for a gym result" do
    draft = complete_draft([ @groups[1] ])
    GymResult.record_beaten!(@run, 1, draft: draft)
    login_as(GREY)
    get gym_ready_path
    assert_select "#gym-ready-team[data-team-source=personal]"
    assert_select "#gym-ready-team", text: /Starly/
    assert_select "#gym-ready-team", text: /Budew/, count: 0
  end
end
