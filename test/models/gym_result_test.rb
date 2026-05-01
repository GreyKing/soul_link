require "test_helper"

class GymResultTest < ActiveSupport::TestCase
  setup do
    @run = create(:soul_link_run)
    @groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
      create(:soul_link_pokemon_group, trait, soul_link_run: @run)
    end
  end

  test "valid with required attributes" do
    result = @run.gym_results.build(gym_number: 1, beaten_at: Time.current)
    assert result.valid?
  end

  test "requires gym_number between 1 and 8" do
    result = @run.gym_results.build(gym_number: 0, beaten_at: Time.current)
    assert_not result.valid?
    result.gym_number = 9
    assert_not result.valid?
    result.gym_number = 4
    assert result.valid?
  end

  test "enforces uniqueness per run" do
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current)
    duplicate = @run.gym_results.build(gym_number: 1, beaten_at: Time.current)
    assert_not duplicate.valid?
  end

  test "snapshot_from_groups builds correct structure" do
    # Seed one pokemon per group so .limit(2) finds groups with pokemon
    # regardless of DB-defined row order (replicates fixture-era state where
    # every group had pokemon attached).
    %i[route201_grey route202_grey route203_grey route204_grey route205_grey route206_grey]
      .each_with_index do |trait, i|
      create(:soul_link_pokemon, trait, soul_link_run: @run, soul_link_pokemon_group: @groups[i])
    end
    groups = @run.soul_link_pokemon_groups.includes(:soul_link_pokemon).limit(2)
    snapshot = GymResult.snapshot_from_groups(groups)
    assert_equal 2, snapshot["groups"].size
    first_group = snapshot["groups"].first
    assert first_group.key?("nickname")
    assert first_group.key?("pokemon")
    assert first_group["pokemon"].first.key?("species")
    assert first_group["pokemon"].first.key?("player_name")
  end
end
