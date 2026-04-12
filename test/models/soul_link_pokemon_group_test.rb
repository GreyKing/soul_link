require "test_helper"

class SoulLinkPokemonGroupTest < ActiveSupport::TestCase
  GREY = 153665622641737728

  setup do
    @run = soul_link_runs(:active_run)
    @group = soul_link_pokemon_groups(:group_route201)
  end

  test "requires nickname and location" do
    group = SoulLinkPokemonGroup.new(soul_link_run: @run, status: "caught")
    assert_not group.valid?
    assert_includes group.errors[:nickname], "can't be blank"
    assert_includes group.errors[:location], "can't be blank"
  end

  test "status must be caught or dead" do
    @group.status = "fainted"
    assert_not @group.valid?
  end

  test "species_for returns pokemon for given user" do
    pokemon = @group.species_for(GREY)
    assert_not_nil pokemon
    assert_equal GREY, pokemon.discord_user_id
  end

  test "species_for returns nil for unknown user" do
    assert_nil @group.species_for(1)
  end

  test "complete? is true when all players have pokemon" do
    assert @group.complete?
  end

  test "mark_as_dead cascades to all pokemon" do
    @group.mark_as_dead!
    @group.soul_link_pokemon.reload.each do |p|
      assert_equal "dead", p.status
      assert_not_nil p.died_at
    end
  end

  test "set_position auto-increments" do
    g1 = @run.soul_link_pokemon_groups.create!(nickname: "TEST1", location: "route_201", status: "caught")
    g2 = @run.soul_link_pokemon_groups.create!(nickname: "TEST2", location: "route_202", status: "caught")
    assert g2.position > g1.position
  end
end
