require "test_helper"

# Server-side read-only mode: once a run has wiped (and not completed), every
# write to its data is refused. Reviving is the exception; see the revive
# tests at the bottom.
class ReadOnlyRunTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run, wiped_at: 1.day.ago)
    @group = create(:soul_link_pokemon_group, soul_link_run: @run)
    @pokemon = create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: @group,
                      discord_user_id: GREY)
    login_as(GREY)
  end

  test "JSON writes to a wiped run are refused with 403" do
    requests = {
      "create group"   => -> { post pokemon_groups_path, params: { nickname: "X", location: "route_201" }, as: :json },
      "edit group"     => -> { patch pokemon_group_path(@group), params: { nickname: "Y" }, as: :json },
      "reorder groups" => -> { patch reorder_pokemon_groups_path, params: { group_ids: [ @group.id ] }, as: :json },
      "delete group"   => -> { delete pokemon_group_path(@group), as: :json },
      "add pokemon"    => -> { post pokemon_index_path, params: { group_id: @group.id, species: "Bidoof" }, as: :json },
      "edit pokemon"   => -> { patch pokemon_path(@pokemon), params: { level: 9 }, as: :json },
      "assign species" => -> { patch assign_species_path, params: {}, as: :json },
      "team slots"     => -> { patch update_slots_team_path, params: { group_ids: [] }, as: :json },
      "gym progress"   => -> { patch gym_progress_path, params: { gym_number: 1 }, as: :json },
      "gym result"     => -> { patch gym_result_path(1), params: { group_ids: [ @group.id ] }, as: :json }
    }

    requests.each do |label, request|
      request.call
      assert_response :forbidden, label
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, response.parsed_body["error"], label
    end
    assert SoulLinkPokemonGroup.exists?(@group.id)
    assert_equal @group.nickname, @group.reload.nickname
  end

  test "form writes to a wiped run redirect to the dashboard with the alert" do
    draft = create(:gym_draft, soul_link_run: @run)
    requests = {
      "start draft"  => -> { post gym_drafts_path },
      "delete draft" => -> { delete gym_draft_path(draft) },
      "mark beaten"  => -> { post mark_beaten_gym_draft_path(draft) },
      "start poll"   => -> { post gym_poll_path },
      "reset poll"   => -> { delete gym_poll_path }
    }

    requests.each do |label, request|
      request.call
      assert_redirected_to root_path, label
      assert_equal SoulLinkRun::READ_ONLY_MESSAGE, flash[:alert], label
    end
    assert GymDraft.exists?(draft.id)
  end

  test "a run that wiped after completing stays editable" do
    @run.update!(completed_at: Time.current)

    patch pokemon_group_path(@group), params: { nickname: "Y" }, as: :json

    assert_response :success
    assert_equal "Y", @group.reload.nickname
  end

  test "a live run is unaffected" do
    @run.update!(wiped_at: nil)

    patch pokemon_group_path(@group), params: { nickname: "Y" }, as: :json

    assert_response :success
  end
end
