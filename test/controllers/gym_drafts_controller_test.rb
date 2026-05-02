require "test_helper"

class GymDraftsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    @draft = create(:gym_draft, :lobby, soul_link_run: @run)
  end

  test "create requires login" do
    post gym_drafts_path
    assert_redirected_to login_path
  end

  test "create makes new draft and redirects to show" do
    @draft.destroy! # remove fixture draft so a new one is created
    login_as(GREY)

    assert_difference "GymDraft.count", 1 do
      post gym_drafts_path
    end

    draft = GymDraft.last
    assert_redirected_to gym_draft_path(draft)
    assert_equal "lobby", draft.status
    assert_equal @run.id, draft.soul_link_run_id
  end

  test "create reuses existing active draft" do
    login_as(GREY)

    assert_no_difference "GymDraft.count" do
      post gym_drafts_path
    end

    assert_redirected_to gym_draft_path(@draft)
  end

  test "show loads draft successfully" do
    login_as(GREY)

    get gym_draft_path(@draft)
    assert_response :success
  end

  test "show loads type analysis for complete draft" do
    login_as(GREY)
    groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
      create(:soul_link_pokemon_group, trait, soul_link_run: @run)
    end

    @draft.update!(
      status: "complete",
      pick_order: [ GREY ],
      state_data: {
        "ready_players" => [],
        "first_pick_votes" => {},
        "picks" => groups.each_with_index.map { |g, i|
          { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY }
        }
      }
    )

    get gym_draft_path(@draft)
    assert_response :success
  end

  test "mark_beaten on complete draft redirects to dashboard Gyms tab" do
    login_as(GREY)
    groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
      create(:soul_link_pokemon_group, trait, soul_link_run: @run)
    end
    @draft.update!(
      status: "complete",
      pick_order: [ GREY ],
      state_data: {
        "ready_players" => [],
        "first_pick_votes" => {},
        "picks" => groups.each_with_index.map { |g, i|
          { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY }
        }
      }
    )

    post mark_beaten_gym_draft_path(@draft)
    assert_redirected_to root_path(anchor: "gyms")
    assert_equal "Gym 1 marked as beaten!", flash[:notice]
    assert_equal 1, @run.reload.gyms_defeated
  end

  test "mark_beaten on incomplete draft redirects to dashboard Gyms tab (not to unrouted gym_drafts_path)" do
    login_as(GREY)
    # @draft is in lobby (not complete) — should hit the early-return guard.

    post mark_beaten_gym_draft_path(@draft)
    assert_redirected_to root_path(anchor: "gyms")
    assert_equal "Draft is not complete.", flash[:alert]
    assert_equal 0, @run.reload.gyms_defeated
  end

  test "destroy active draft removes it" do
    login_as(GREY)

    delete gym_draft_path(@draft)
    assert_response :success
    assert_not GymDraft.exists?(@draft.id)
  end

  test "destroy complete draft is rejected (status guard)" do
    login_as(GREY)
    @draft.update!(status: "complete")

    delete gym_draft_path(@draft)
    assert_response :unprocessable_entity
    assert GymDraft.exists?(@draft.id)
  end

  test "destroy returns 404 for cross-guild access" do
    login_as(GREY)
    other_run = create(:soul_link_run, guild_id: 111111111111111111, active: false)
    other_draft = create(:gym_draft, :lobby, soul_link_run: other_run)

    delete gym_draft_path(other_draft)
    assert_response :not_found
    assert GymDraft.exists?(other_draft.id)
  end

  # --- Step 15: mark_beaten clears matching suppression ----------------------

  test "mark_beaten clears any matching gym_auto_mark_suppression" do
    login_as(GREY)
    groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
      create(:soul_link_pokemon_group, trait, soul_link_run: @run)
    end
    @draft.update!(
      status: "complete",
      pick_order: [ GREY ],
      state_data: {
        "ready_players" => [],
        "first_pick_votes" => {},
        "picks" => groups.each_with_index.map { |g, i|
          { "round" => i + 1, "group_id" => g.id, "picked_by" => GREY }
        }
      }
    )

    @run.gym_auto_mark_suppressions.create!(gym_number: 1)

    assert_difference "@run.gym_auto_mark_suppressions.count", -1 do
      post mark_beaten_gym_draft_path(@draft)
    end
    assert_not @run.gym_auto_mark_suppressions.exists?(gym_number: 1)
    assert @run.gym_results.exists?(gym_number: 1)
  end
end
