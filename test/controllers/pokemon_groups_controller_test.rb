require "test_helper"

class PokemonGroupsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
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
    group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
    patch pokemon_group_path(group), params: { status: "dead" }, as: :json
    assert_response :success
    group.reload
    assert_equal "dead", group.status
  end

  test "destroy removes group" do
    login_as(GREY)
    group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
    assert_difference "SoulLinkPokemonGroup.count", -1 do
      delete pokemon_group_path(group), as: :json
    end
    assert_response :success
  end

  test "creating a group posts the catch embed once" do
    login_as(GREY)
    calls = []

    SoulLink::CatchMessage.stub(:post_or_update, ->(group) { calls << group.id }) do
      post pokemon_groups_path, params: {
        nickname: "TOMMY", location: "route_205"
      }, as: :json
    end

    assert_response :success
    assert_equal 1, calls.length
  end

  test "updating a group re-syncs the catch embed" do
    login_as(GREY)
    group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
    calls = []

    SoulLink::CatchMessage.stub(:post_or_update, ->(g) { calls << g.id }) do
      patch pokemon_group_path(group), params: { nickname: "RENAMED" }, as: :json
    end

    assert_response :success
    assert_equal [ group.id ], calls
  end

  test "destroying a group deletes the catch embed before the row is gone" do
    login_as(GREY)
    group = create(:soul_link_pokemon_group, :route206, soul_link_run: @run)
    seen_ids = []

    SoulLink::CatchMessage.stub(:delete, ->(g) { seen_ids << g.id }) do
      delete pokemon_group_path(group), as: :json
    end

    assert_response :success
    assert_equal [ group.id ], seen_ids
  end
end
