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

  # --- record_beaten! -------------------------------------------------------

  def complete_draft(groups, **attrs)
    create(:gym_draft, soul_link_run: @run, status: "complete",
      state_data: { "ready_players" => [], "first_pick_votes" => {},
                    "picks" => groups.each_with_index.map { |g, i| { "round" => i + 1, "group_id" => g.id, "picked_by" => 1 } } },
      **attrs)
  end

  test "record_beaten! links the newest unattached complete draft and snapshots its team" do
    create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: @groups[0])
    complete_draft(@groups[3..4], updated_at: 2.hours.ago)
    newest = complete_draft(@groups[0..1], updated_at: 1.hour.ago)

    result = GymResult.record_beaten!(@run, 1)

    assert_equal newest, result.gym_draft
    assert_equal @groups[0..1].map(&:id), result.team_snapshot["groups"].map { |g| g["group_id"] }
    assert_equal 1, @run.reload.gyms_defeated
  end

  test "record_beaten! does not reuse a draft already attached to a result" do
    used = complete_draft(@groups[0..1])
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current, gym_draft: used)

    result = GymResult.record_beaten!(@run, 2)

    assert_nil result.gym_draft
    assert_nil result.team_snapshot
  end

  test "record_beaten! ignores non-complete drafts" do
    create(:gym_draft, soul_link_run: @run, status: "drafting")

    result = GymResult.record_beaten!(@run, 1)

    assert_nil result.gym_draft
  end

  test "record_beaten! prefers an explicitly passed draft" do
    complete_draft(@groups[0..1])
    explicit = complete_draft(@groups[2..3], updated_at: 1.day.ago)

    result = GymResult.record_beaten!(@run, 1, draft: explicit)

    assert_equal explicit, result.gym_draft
  end

  test "record_beaten! never lowers gyms_defeated" do
    @run.update!(gyms_defeated: 5)
    GymResult.record_beaten!(@run, 2)
    assert_equal 5, @run.reload.gyms_defeated
  end
end
