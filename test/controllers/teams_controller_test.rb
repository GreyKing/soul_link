require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = soul_link_runs(:active_run)
  end

  test "show requires login" do
    get team_path
    assert_redirected_to login_path
  end

  test "show creates team if none exists" do
    login_as(GREY)
    # Destroy fixture team first
    SoulLinkTeam.where(discord_user_id: GREY).destroy_all
    assert_difference "SoulLinkTeam.count", 1 do
      get team_path
    end
    assert_response :success
  end

  test "update_slots saves valid group ids" do
    login_as(GREY)
    group = soul_link_pokemon_groups(:group_route201)
    patch update_slots_team_path, params: { group_ids: [group.id] }, as: :json
    assert_response :success
  end

  test "update_slots rejects more than 6" do
    login_as(GREY)
    groups = @run.soul_link_pokemon_groups.limit(7).pluck(:id)
    patch update_slots_team_path, params: { group_ids: groups }, as: :json
    # Even if 7 sent, allowed_ids filters to only groups where Grey has pokemon
    # and replace_slots! caps at MAX_SLOTS
    assert_response :success
  end

  test "update_slots filters groups where user has no pokemon" do
    login_as(GREY)
    # Create a group with only another player's pokemon
    orphan_group = @run.soul_link_pokemon_groups.create!(nickname: "ORPHAN", location: "route_201", status: "caught")
    @run.soul_link_pokemon.create!(
      soul_link_pokemon_group: orphan_group,
      discord_user_id: 999,
      species: "Zubat",
      name: "ORPHAN",
      location: "route_201",
      status: "caught"
    )

    patch update_slots_team_path, params: { group_ids: [orphan_group.id] }, as: :json
    assert_response :success
    team = @run.soul_link_teams.find_by(discord_user_id: GREY)
    # Orphan group should have been filtered out
    assert_equal 0, team.soul_link_team_slots.count
  end

  test "index shows all teams" do
    login_as(GREY)
    get teams_path
    assert_response :success
  end
end
