require "test_helper"

class GymDraftsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = soul_link_runs(:active_run)
    @draft = gym_drafts(:lobby_draft)
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
    groups = [
      soul_link_pokemon_groups(:group_route201),
      soul_link_pokemon_groups(:group_route202),
      soul_link_pokemon_groups(:group_route203),
      soul_link_pokemon_groups(:group_route204),
      soul_link_pokemon_groups(:group_route205),
      soul_link_pokemon_groups(:group_route206)
    ]

    @draft.update!(
      status: "complete",
      pick_order: [GREY],
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
end
