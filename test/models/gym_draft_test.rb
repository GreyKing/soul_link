require "test_helper"

class GymDraftTest < ActiveSupport::TestCase
  GREY    = 153665622641737728
  ARATY   = 600802903967531093
  SCYTHE  = 189518174125817856
  ZEALOUS = 182742127061630976
  ALL_PLAYERS = [GREY, ARATY, SCYTHE, ZEALOUS].freeze

  setup do
    @run = soul_link_runs(:active_run)
    @draft = gym_drafts(:lobby_draft)
    @groups = [
      soul_link_pokemon_groups(:group_route201),
      soul_link_pokemon_groups(:group_route202),
      soul_link_pokemon_groups(:group_route203),
      soul_link_pokemon_groups(:group_route204),
      soul_link_pokemon_groups(:group_route205),
      soul_link_pokemon_groups(:group_route206)
    ]
  end

  # ── Lobby Phase ──

  test "new draft starts in lobby with empty state" do
    draft = @run.gym_drafts.create!
    assert_equal "lobby", draft.status
    assert_equal [], draft.ready_players
    assert_equal({}, draft.first_pick_votes)
    assert_equal [], draft.picks
    assert_equal 0, draft.current_round
    assert_equal 0, draft.current_player_index
  end

  test "mark_ready adds player to ready list" do
    @draft.mark_ready!(GREY)
    assert_includes @draft.ready_players, GREY
    assert_equal "lobby", @draft.status
  end

  test "mark_ready is idempotent" do
    @draft.mark_ready!(GREY)
    @draft.mark_ready!(GREY)
    assert_equal 1, @draft.ready_players.count(GREY)
  end

  test "mark_ready raises when not in lobby" do
    @draft.update!(status: "voting")
    assert_raises(RuntimeError, "Not in lobby") { @draft.mark_ready!(GREY) }
  end

  test "all players ready transitions to voting" do
    ALL_PLAYERS.each { |uid| @draft.mark_ready!(uid) }
    @draft.reload
    assert_equal "voting", @draft.status
  end

  # ── Voting Phase ──

  test "cast_vote records vote" do
    move_to_voting!
    @draft.cast_vote!(GREY, ARATY)
    assert_equal ARATY, @draft.first_pick_votes[GREY.to_s]
  end

  test "cast_vote raises when not in voting phase" do
    assert_raises(RuntimeError, "Not in voting phase") { @draft.cast_vote!(GREY, ARATY) }
  end

  test "all voted transitions to drafting with pick_order" do
    move_to_voting!
    ALL_PLAYERS.each { |uid| @draft.cast_vote!(uid, GREY) }
    @draft.reload
    assert_equal "drafting", @draft.status
    assert_equal GREY, @draft.pick_order.first
    assert_equal 4, @draft.pick_order.size
  end

  test "vote tiebreak picks a valid winner" do
    move_to_voting!
    # 2 votes for Grey, 2 votes for Araty — tiebreak
    @draft.cast_vote!(GREY, GREY)
    @draft.cast_vote!(ARATY, ARATY)
    @draft.cast_vote!(SCYTHE, GREY)
    @draft.cast_vote!(ZEALOUS, ARATY)
    @draft.reload
    assert_equal "drafting", @draft.status
    assert_includes [GREY, ARATY], @draft.pick_order.first
    assert_equal 4, @draft.pick_order.size
  end

  # ── Drafting Phase ──

  test "make_pick records pick and advances turn" do
    move_to_drafting!(first_picker: GREY)
    @draft.make_pick!(GREY, @groups[0].id)
    @draft.reload
    assert_equal 1, @draft.picks.size
    assert_equal @groups[0].id, @draft.picks.first["group_id"]
    assert_equal GREY, @draft.picks.first["picked_by"]
    assert_equal 1, @draft.current_player_index
  end

  test "make_pick raises when not your turn" do
    move_to_drafting!(first_picker: GREY)
    assert_raises(RuntimeError, "Not your turn") { @draft.make_pick!(ARATY, @groups[0].id) }
  end

  test "make_pick raises when not in drafting phase" do
    assert_raises(RuntimeError, "Not in drafting phase") { @draft.make_pick!(GREY, @groups[0].id) }
  end

  test "make_pick raises for duplicate group" do
    move_to_drafting!(first_picker: GREY)
    @draft.make_pick!(GREY, @groups[0].id)
    @draft.reload
    # Next player tries to pick the same group
    next_player = @draft.pick_order[@draft.current_player_index]
    assert_raises(RuntimeError, "That pokemon has already been picked") do
      @draft.make_pick!(next_player, @groups[0].id)
    end
  end

  test "four picks transitions to nominating" do
    move_to_drafting!(first_picker: GREY)
    pick_order = @draft.pick_order
    4.times do |i|
      picker = pick_order[i]
      @draft.reload
      @draft.make_pick!(picker, @groups[i].id)
    end
    @draft.reload
    assert_equal "nominating", @draft.status
    assert_equal 4, @draft.picks.size
  end

  # ── Nominating Phase ──

  test "submit_nomination creates nomination with nominator auto-vote" do
    move_to_nominating!
    @draft.submit_nomination!(GREY, @groups[4].id)
    @draft.reload
    nom = @draft.current_nomination
    assert_equal GREY, nom["nominator_id"]
    assert_equal @groups[4].id, nom["group_id"]
    assert_equal true, nom["votes"][GREY.to_s]
  end

  test "submit_nomination raises for already picked group" do
    move_to_nominating!
    picked_group_id = @draft.picks.first["group_id"]
    assert_raises(RuntimeError, "That pokemon has already been picked") do
      @draft.submit_nomination!(GREY, picked_group_id)
    end
  end

  test "submit_nomination raises when nomination is pending" do
    move_to_nominating!
    @draft.submit_nomination!(GREY, @groups[4].id)
    @draft.reload
    assert_raises(RuntimeError, "Already have a pending nomination") do
      @draft.submit_nomination!(ARATY, @groups[5].id)
    end
  end

  test "vote_on_nomination records vote" do
    move_to_nominating!
    @draft.submit_nomination!(GREY, @groups[4].id)
    @draft.reload
    @draft.vote_on_nomination!(ARATY, true)
    @draft.reload
    assert_equal true, @draft.current_nomination["votes"][ARATY.to_s]
  end

  test "nomination approved with majority adds pick" do
    move_to_nominating!
    picks_before = @draft.picks.size
    @draft.submit_nomination!(GREY, @groups[4].id)
    @draft.reload
    @draft.vote_on_nomination!(ARATY, true)
    @draft.reload
    @draft.vote_on_nomination!(SCYTHE, true)
    @draft.reload
    # 2 out of 3 others approved — pick should be added
    assert_equal picks_before + 1, @draft.picks.size
    assert_equal @groups[4].id, @draft.picks.last["group_id"]
    assert_nil @draft.current_nomination
  end

  test "nomination rejected clears nomination without adding pick" do
    move_to_nominating!
    picks_before = @draft.picks.size
    @draft.submit_nomination!(GREY, @groups[4].id)
    @draft.reload
    @draft.vote_on_nomination!(ARATY, false)
    @draft.reload
    @draft.vote_on_nomination!(SCYTHE, false)
    @draft.reload
    assert_equal picks_before, @draft.picks.size
    assert_nil @draft.current_nomination
  end

  test "six total picks transitions to complete" do
    move_to_nominating!
    # We have 4 picks from drafting. Nominate and approve 2 more.
    @draft.submit_nomination!(GREY, @groups[4].id)
    @draft.reload
    @draft.vote_on_nomination!(ARATY, true)
    @draft.reload
    @draft.vote_on_nomination!(SCYTHE, true)
    @draft.reload
    assert_equal "nominating", @draft.status

    @draft.submit_nomination!(ARATY, @groups[5].id)
    @draft.reload
    @draft.vote_on_nomination!(GREY, true)
    @draft.reload
    @draft.vote_on_nomination!(SCYTHE, true)
    @draft.reload
    assert_equal "complete", @draft.status
    assert_equal 6, @draft.picks.size
  end

  # ── Broadcast State ──

  test "broadcast_state converts discord IDs to strings" do
    move_to_drafting!(first_picker: GREY)
    @draft.make_pick!(GREY, @groups[0].id)
    @draft.reload
    state = @draft.broadcast_state

    # Player IDs should be strings
    state[:player_ids].each { |id| assert_kind_of String, id }
    state[:ready_players].each { |id| assert_kind_of String, id }
    state[:pick_order].each { |id| assert_kind_of String, id }

    # Picks picked_by should be strings
    state[:picks].each { |p| assert_kind_of String, p["picked_by"] }

    # Current drafter should be string
    assert_kind_of String, state[:current_drafter_id] if state[:current_drafter_id]

    # Players should have string discord_user_id
    state[:players].each { |p| assert_kind_of String, p["discord_user_id"] }
  end

  private

  def move_to_voting!
    ALL_PLAYERS.each { |uid| @draft.mark_ready!(uid) }
    @draft.reload
  end

  def move_to_drafting!(first_picker:)
    move_to_voting!
    # Everyone votes for the desired first picker
    ALL_PLAYERS.each { |uid| @draft.cast_vote!(uid, first_picker) }
    @draft.reload
  end

  def move_to_nominating!
    move_to_drafting!(first_picker: GREY)
    pick_order = @draft.pick_order
    4.times do |i|
      picker = pick_order[i]
      @draft.reload
      @draft.make_pick!(picker, @groups[i].id)
    end
    @draft.reload
  end
end
