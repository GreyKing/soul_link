require "test_helper"

class PokemonGroupsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = soul_link_runs(:active_run)
  end

  test "create requires login" do
    post pokemon_groups_path, params: { nickname: "TEST", location: "route_201" }, as: :json
    assert_redirected_to login_path
  end

  test "create with valid params creates group" do
    login_as(GREY)
    assert_difference "SoulLinkPokemonGroup.count", 1 do
      post pokemon_groups_path, params: { nickname: "NEWGROUP", location: "route_201" }, as: :json
    end
    assert_response :success
  end

  test "create with blank nickname returns error" do
    login_as(GREY)
    post pokemon_groups_path, params: { nickname: "", location: "route_201" }, as: :json
    assert_response :unprocessable_entity
  end

  test "create skips blank species" do
    login_as(GREY)
    post pokemon_groups_path, params: {
      nickname: "SKIP", location: "route_201",
      species: { GREY.to_s => "Starly", "999" => "" }
    }, as: :json
    assert_response :success
    group = SoulLinkPokemonGroup.find_by(nickname: "SKIP")
    assert_equal 1, group.soul_link_pokemon.count
  end

  test "update to dead cascades status" do
    login_as(GREY)
    group = soul_link_pokemon_groups(:group_route206)
    patch pokemon_group_path(group), params: { status: "dead" }, as: :json
    assert_response :success
    group.reload
    assert_equal "dead", group.status
  end

  test "destroy removes group" do
    login_as(GREY)
    group = soul_link_pokemon_groups(:group_route206)
    assert_difference "SoulLinkPokemonGroup.count", -1 do
      delete pokemon_group_path(group), as: :json
    end
    assert_response :success
  end
end
