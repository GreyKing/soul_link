require "test_helper"

class SpeciesAssignmentsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = soul_link_runs(:active_run)
  end

  test "show requires login" do
    get species_path
    assert_redirected_to login_path
  end

  test "show loads successfully" do
    login_as(GREY)
    get species_path
    assert_response :success
  end

  test "assign_from_pokedex creates pokemon in group" do
    login_as(GREY)
    group = @run.soul_link_pokemon_groups.create!(nickname: "ASSIGN", location: "route_201", status: "caught")

    patch assign_from_pokedex_species_path, params: { species_name: "Starly", group_id: group.id }, as: :json
    assert_response :success
    assert group.species_for(GREY)
  end

  test "assign_from_pokedex rejects duplicate user in group" do
    login_as(GREY)
    group = soul_link_pokemon_groups(:group_route201)
    # Grey already has pokemon in this group
    patch assign_from_pokedex_species_path, params: { species_name: "Bidoof", group_id: group.id }, as: :json
    assert_response :unprocessable_entity
  end

  test "unassign removes pokemon from group" do
    login_as(GREY)
    # Create an assigned pokemon, then unassign
    group = @run.soul_link_pokemon_groups.create!(nickname: "UNTEST", location: "route_201", status: "caught")
    pokemon = @run.soul_link_pokemon.create!(
      soul_link_pokemon_group: group,
      discord_user_id: GREY,
      species: "Geodude",
      name: "UNTEST",
      location: "route_201",
      status: "caught"
    )
    patch unassign_species_path, params: { pokemon_id: pokemon.id }, as: :json
    assert_response :success
    pokemon.reload
    assert_nil pokemon.soul_link_pokemon_group_id
  end
end
