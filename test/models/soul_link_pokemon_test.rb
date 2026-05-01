require "test_helper"

class SoulLinkPokemonTest < ActiveSupport::TestCase
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    @group_201 = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
    @group_202 = create(:soul_link_pokemon_group, :route202, soul_link_run: @run)
    @pokemon = create(:soul_link_pokemon, :route201_grey,
                     soul_link_run: @run,
                     soul_link_pokemon_group: @group_201)
  end

  test "factory pokemon is valid" do
    assert @pokemon.valid?
  end

  test "requires species when assigned to group" do
    @pokemon.species = ""
    assert_not @pokemon.valid?
    assert_includes @pokemon.errors[:species], "can't be blank"
  end

  test "enforces unique discord_user_id per group" do
    duplicate = SoulLinkPokemon.new(
      soul_link_run: @pokemon.soul_link_run,
      soul_link_pokemon_group: @pokemon.soul_link_pokemon_group,
      discord_user_id: @pokemon.discord_user_id,
      species: "Bidoof",
      name: "Test",
      location: "route_201",
      status: "caught"
    )
    assert_not duplicate.valid?
  end

  test "assign_to_group sets group and syncs name and location" do
    pokemon = @run.soul_link_pokemon.create!(
      discord_user_id: 999999999999999999,
      species: "Zubat",
      name: "temp",
      location: "temp",
      status: "caught"
    )
    pokemon.assign_to_group!(@group_201)
    pokemon.reload
    assert_equal @group_201.id, pokemon.soul_link_pokemon_group_id
    assert_equal @group_201.nickname, pokemon.name
    assert_equal @group_201.location, pokemon.location
  end

  test "assign_to_group raises if already assigned" do
    assert_raises(RuntimeError) { @pokemon.assign_to_group!(@group_202) }
  end

  test "mark_as_dead sets status and died_at" do
    @pokemon.mark_as_dead!
    assert_equal "dead", @pokemon.status
    assert_not_nil @pokemon.died_at
  end

  test "caught? and dead? reflect status" do
    assert @pokemon.caught?
    assert_not @pokemon.dead?
    @pokemon.mark_as_dead!
    assert @pokemon.dead?
    assert_not @pokemon.caught?
  end
end
