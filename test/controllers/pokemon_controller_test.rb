require "test_helper"

class PokemonControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728
  ARATY = 600802903967531093

  setup do
    @run = soul_link_runs(:active_run)
  end

  test "create requires login" do
    post pokemon_index_path, as: :json
    assert_redirected_to login_path
  end

  test "create adds pokemon to group for current user" do
    login_as(GREY)
    # Create a fresh group with no pokemon for Grey
    group = @run.soul_link_pokemon_groups.create!(nickname: "EMPTY", location: "route_201", status: "caught")

    assert_difference "SoulLinkPokemon.count", 1 do
      post pokemon_index_path, params: { group_id: group.id, species: "Pikachu" }, as: :json
    end
    assert_response :success
  end

  test "create rejects duplicate user in group" do
    login_as(GREY)
    group = soul_link_pokemon_groups(:group_route201)
    # Grey already has a pokemon in this group via fixtures
    post pokemon_index_path, params: { group_id: group.id, species: "Bidoof" }, as: :json
    assert_response :unprocessable_entity
  end

  test "create rejects missing species" do
    login_as(GREY)
    group = @run.soul_link_pokemon_groups.create!(nickname: "EMPTY2", location: "route_201", status: "caught")
    post pokemon_index_path, params: { group_id: group.id, species: "" }, as: :json
    assert_response :unprocessable_entity
  end

  test "update rejects other players pokemon" do
    login_as(GREY)
    araty_pokemon = soul_link_pokemon(:pkmn_route201_aratypuss)
    patch pokemon_path(araty_pokemon), params: { species: "Hacked" }, as: :json
    assert_response :forbidden
  end
end
