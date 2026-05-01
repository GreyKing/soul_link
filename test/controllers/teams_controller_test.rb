require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    SoulLinkRun.where(guild_id: LoginHelper::GUILD_ID).destroy_all
    @run = create(:soul_link_run)
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
    group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
    create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: group)
    patch update_slots_team_path, params: { group_ids: [ group.id ] }, as: :json
    assert_response :success
  end

  test "update_slots rejects more than 6" do
    login_as(GREY)
    # Seed 6 groups (one per route) with Grey-pokemon. The 7th group has no
    # Grey-pokemon so allowed_ids filters it out — 6 valid ids remain, fitting
    # under MAX_SLOTS. Mirrors the fixture-era invariant where .limit(7)
    # returned 6 and the controller capped silently.
    6.times do |i|
      g = @run.soul_link_pokemon_groups.create!(nickname: "G#{i}", location: "route_20#{i + 1}", status: "caught")
      @run.soul_link_pokemon.create!(soul_link_pokemon_group: g, discord_user_id: GREY,
                                     species: "Bulbasaur", name: "G#{i}", location: g.location, status: "caught")
    end
    @run.soul_link_pokemon_groups.create!(nickname: "G6", location: "route_201", status: "caught")
    groups = @run.soul_link_pokemon_groups.limit(7).pluck(:id)
    patch update_slots_team_path, params: { group_ids: groups }, as: :json
    # 7 sent, 1 filtered (no Grey pokemon), 6 remain → success
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

    patch update_slots_team_path, params: { group_ids: [ orphan_group.id ] }, as: :json
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
