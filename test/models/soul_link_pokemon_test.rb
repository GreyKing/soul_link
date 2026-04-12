require "test_helper"

class SoulLinkPokemonTest < ActiveSupport::TestCase
  GREY = 153665622641737728

  test "fixture pokemon is valid" do
    pokemon = soul_link_pokemon(:pkmn_route201_grey)
    assert pokemon.valid?
  end

  test "requires species when assigned to group" do
    pokemon = soul_link_pokemon(:pkmn_route201_grey)
    pokemon.species = ""
    assert_not pokemon.valid?
    assert_includes pokemon.errors[:species], "can't be blank"
  end

  test "enforces unique discord_user_id per group" do
    existing = soul_link_pokemon(:pkmn_route201_grey)
    duplicate = SoulLinkPokemon.new(
      soul_link_run: existing.soul_link_run,
      soul_link_pokemon_group: existing.soul_link_pokemon_group,
      discord_user_id: existing.discord_user_id,
      species: "Bidoof",
      name: "Test",
      location: "route_201",
      status: "caught"
    )
    assert_not duplicate.valid?
  end

  test "assign_to_group sets group and syncs name and location" do
    run = soul_link_runs(:active_run)
    group = soul_link_pokemon_groups(:group_route201)
    pokemon = run.soul_link_pokemon.create!(
      discord_user_id: 999999999999999999,
      species: "Zubat",
      name: "temp",
      location: "temp",
      status: "caught"
    )
    pokemon.assign_to_group!(group)
    pokemon.reload
    assert_equal group.id, pokemon.soul_link_pokemon_group_id
    assert_equal group.nickname, pokemon.name
    assert_equal group.location, pokemon.location
  end

  test "assign_to_group raises if already assigned" do
    pokemon = soul_link_pokemon(:pkmn_route201_grey)
    group = soul_link_pokemon_groups(:group_route202)
    assert_raises(RuntimeError) { pokemon.assign_to_group!(group) }
  end

  test "mark_as_dead sets status and died_at" do
    pokemon = soul_link_pokemon(:pkmn_route201_grey)
    pokemon.mark_as_dead!
    assert_equal "dead", pokemon.status
    assert_not_nil pokemon.died_at
  end

  test "caught? and dead? reflect status" do
    pokemon = soul_link_pokemon(:pkmn_route201_grey)
    assert pokemon.caught?
    assert_not pokemon.dead?
    pokemon.mark_as_dead!
    assert pokemon.dead?
    assert_not pokemon.caught?
  end
end
