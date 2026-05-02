require "test_helper"

class GymDraftTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  GREY    = 153665622641737728
  ARATY   = 600802903967531093
  SCYTHE  = 189518174125817856
  ZEALOUS = 182742127061630976
  ALL_PLAYERS = [ GREY, ARATY, SCYTHE, ZEALOUS ].freeze

  setup do
    @run = create(:soul_link_run)
    @groups = %i[route201 route202 route203 route204 route205 route206].map do |trait|
      create(:soul_link_pokemon_group, trait, soul_link_run: @run)
    end
    @draft = create(:gym_draft, :lobby, soul_link_run: @run)
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
    assert_includes [ GREY, ARATY ], @draft.pick_order.first
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

  test "current_turn_started_at is set on transition into nominating" do
    move_to_drafting!(first_picker: GREY)
    pick_order = @draft.pick_order
    4.times do |i|
      picker = pick_order[i]
      @draft.reload
      @draft.make_pick!(picker, @groups[i].id)
    end
    @draft.reload
    assert @draft.current_turn_started_at.present?
    assert @draft.state_data["current_turn_started_at"].present?
  end

  # ── Nominating Phase — Step 14 unified nominate-or-endorse model ──

  test "nominate creates a new candidate" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    @draft.nominate!(nominator, @groups[4].id)
    @draft.reload
    assert_equal 1, @draft.candidates.size
    cand = @draft.candidates.first
    assert_equal @groups[4].id, cand["group_id"]
    assert_equal [ nominator ], cand["voters"]
  end

  test "endorsement adds voter to existing candidate" do
    move_to_nominating!
    first = @draft.current_nominator_id
    @draft.nominate!(first, @groups[4].id)
    @draft.reload
    second = @draft.current_nominator_id
    @draft.nominate!(second, @groups[4].id)
    @draft.reload
    assert_equal 1, @draft.candidates.size
    assert_equal [ first, second ], @draft.candidates.first["voters"]
  end

  test "nominate raises for already-picked individual group" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    picked_group_id = @draft.picks.first["group_id"]
    assert_raises(RuntimeError, "That pokemon has already been picked") do
      @draft.nominate!(nominator, picked_group_id)
    end
  end

  test "nominate raises when not your turn" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    other = (ALL_PLAYERS - [ nominator ]).first
    assert_raises(RuntimeError, "Not your turn to nominate") do
      @draft.nominate!(other, @groups[4].id)
    end
  end

  test "double-endorse by same player raises" do
    # Defensive: current_player_index should prevent this naturally,
    # but we keep the safety belt for races / direct model calls.
    move_to_nominating!
    nominator = @draft.current_nominator_id
    @draft.nominate!(nominator, @groups[4].id)
    @draft.reload
    # Force the index back so the same player tries again
    @draft.update!(current_player_index: @draft.pick_order.index(nominator))
    @draft.reload
    assert_raises(RuntimeError, "You already endorsed this nomination") do
      @draft.nominate!(nominator, @groups[4].id)
    end
  end

  test "current_turn_started_at advances on each nominate" do
    move_to_nominating!
    initial = @draft.current_turn_started_at
    travel 5.seconds do
      nominator = @draft.current_nominator_id
      @draft.nominate!(nominator, @groups[4].id)
      @draft.reload
      after = @draft.current_turn_started_at
      assert after.present?
      assert after > initial, "turn timestamp should advance after a nominate"
    end
  end

  # ── Resolution: 5 tally splits + 1 consensus edge case ──

  test "tally 3/1 — A wins slot 5, B wins slot 6, no tiebreak" do
    move_to_nominating!
    order = @draft.pick_order
    # Players 0,1,2 endorse @groups[4]; player 3 nominates @groups[5].
    @draft.nominate!(order[0], @groups[4].id); @draft.reload
    @draft.nominate!(order[1], @groups[4].id); @draft.reload
    @draft.nominate!(order[2], @groups[4].id); @draft.reload
    @draft.nominate!(order[3], @groups[5].id); @draft.reload

    assert_equal "complete", @draft.status
    assert_equal 6, @draft.picks.size
    assert_equal @groups[4].id, @draft.picks[4]["group_id"]
    assert_equal @groups[5].id, @draft.picks[5]["group_id"]
    assert_nil @draft.tiebreak
  end

  test "tally 2/2 — both fill slots 5+6 with no tiebreak" do
    move_to_nominating!
    order = @draft.pick_order
    @draft.nominate!(order[0], @groups[4].id); @draft.reload
    @draft.nominate!(order[1], @groups[4].id); @draft.reload
    @draft.nominate!(order[2], @groups[5].id); @draft.reload
    @draft.nominate!(order[3], @groups[5].id); @draft.reload

    assert_equal "complete", @draft.status
    assert_equal 6, @draft.picks.size
    final_ids = @draft.picks.last(2).map { |p| p["group_id"] }.sort
    assert_equal [ @groups[4].id, @groups[5].id ].sort, final_ids
    assert_nil @draft.tiebreak
  end

  test "tally 2/1/1 — A picked, second-place tied between B and C" do
    move_to_nominating!
    order = @draft.pick_order
    @draft.nominate!(order[0], @groups[4].id); @draft.reload  # A
    @draft.nominate!(order[1], @groups[4].id); @draft.reload  # endorse A
    @draft.nominate!(order[2], @groups[5].id); @draft.reload  # B
    # Need a 6th group not in the first 4 picks:
    extra = create(:soul_link_pokemon_group, soul_link_run: @run)
    @draft.nominate!(order[3], extra.id); @draft.reload  # C

    assert_equal "complete", @draft.status
    assert_equal 6, @draft.picks.size
    # Slot 5 must be A
    assert_equal @groups[4].id, @draft.picks[4]["group_id"]
    # Slot 6 is one of B or C
    assert_includes [ @groups[5].id, extra.id ], @draft.picks[5]["group_id"]
    tb = @draft.tiebreak
    assert_not_nil tb
    assert_equal "second_place", tb["type"]
    assert_equal [ @groups[5].id, extra.id ].sort, tb["tied_group_ids"].sort
    assert_equal 1, tb["winners"].size
    assert_includes [ @groups[5].id, extra.id ], tb["winners"].first
  end

  test "tally 1/1/1/1 — n_way tie, picks 2 random winners" do
    move_to_nominating!
    order = @draft.pick_order
    extra1 = create(:soul_link_pokemon_group, soul_link_run: @run)
    extra2 = create(:soul_link_pokemon_group, soul_link_run: @run)

    @draft.nominate!(order[0], @groups[4].id); @draft.reload
    @draft.nominate!(order[1], @groups[5].id); @draft.reload
    @draft.nominate!(order[2], extra1.id);     @draft.reload
    @draft.nominate!(order[3], extra2.id);     @draft.reload

    assert_equal "complete", @draft.status
    assert_equal 6, @draft.picks.size
    tb = @draft.tiebreak
    assert_not_nil tb
    assert_equal "n_way", tb["type"]
    assert_equal [ @groups[4].id, @groups[5].id, extra1.id, extra2.id ].sort, tb["tied_group_ids"].sort
    assert_equal 2, tb["winners"].size
    final_ids = @draft.picks.last(2).map { |p| p["group_id"] }.sort
    assert_equal tb["winners"].sort, final_ids
  end

  test "tally 4/0 consensus — only candidate fills slot 5; slot 6 stays empty" do
    move_to_nominating!
    order = @draft.pick_order
    order.each do |uid|
      @draft.nominate!(uid, @groups[4].id)
      @draft.reload
    end

    assert_equal "complete", @draft.status
    # Team has 5 picks, not 6 — intentional per brief.
    assert_equal 5, @draft.picks.size
    assert_equal @groups[4].id, @draft.picks[4]["group_id"]
    # Single-candidate consensus is not a tie — no tiebreak payload.
    assert_nil @draft.tiebreak
  end

  test "tiebreak is nil in state_data when no tie occurred" do
    move_to_nominating!
    order = @draft.pick_order
    @draft.nominate!(order[0], @groups[4].id); @draft.reload
    @draft.nominate!(order[1], @groups[4].id); @draft.reload
    @draft.nominate!(order[2], @groups[4].id); @draft.reload
    @draft.nominate!(order[3], @groups[5].id); @draft.reload

    assert_nil @draft.tiebreak
    assert_nil @draft.state_data["tiebreak"]
  end

  # ── Skip auth (Step 14 — 60s grace) ──

  test "grace_elapsed? returns true after 60s" do
    move_to_nominating!
    travel 65.seconds do
      assert @draft.grace_elapsed?
    end
  end

  test "grace_elapsed? returns false within 60s" do
    move_to_nominating!
    travel 30.seconds do
      assert_not @draft.grace_elapsed?
    end
  end

  test "skip_turn raises if requester is not current nominator and grace not elapsed" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    other = (ALL_PLAYERS - [ nominator ]).first
    assert_raises(RuntimeError, "Not your turn (skip available to others after 60s)") do
      @draft.skip_turn!(other)
    end
  end

  test "skip_turn succeeds for current nominator any time" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    before_index = @draft.current_player_index
    @draft.skip_turn!(nominator)
    @draft.reload
    assert_not_equal before_index, @draft.current_player_index
  end

  test "skip_turn succeeds for non-nominator after grace" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    other = (ALL_PLAYERS - [ nominator ]).first
    travel 65.seconds do
      before_index = @draft.current_player_index
      @draft.skip_turn!(other)
      @draft.reload
      assert_not_equal before_index, @draft.current_player_index
    end
  end

  # ── Broadcast State ──

  test "broadcast_state converts discord IDs to strings" do
    move_to_drafting!(first_picker: GREY)
    @draft.make_pick!(GREY, @groups[0].id)
    @draft.reload
    state = @draft.broadcast_state

    state[:player_ids].each { |id| assert_kind_of String, id }
    state[:ready_players].each { |id| assert_kind_of String, id }
    state[:pick_order].each { |id| assert_kind_of String, id }
    state[:picks].each { |p| assert_kind_of String, p["picked_by"] }
    assert_kind_of String, state[:current_drafter_id] if state[:current_drafter_id]
    state[:players].each { |p| assert_kind_of String, p["discord_user_id"] }
  end

  test "broadcast_state includes Step 14 nominating fields" do
    move_to_nominating!
    nominator = @draft.current_nominator_id
    @draft.nominate!(nominator, @groups[4].id)
    @draft.reload
    state = @draft.broadcast_state

    assert state.key?(:candidates)
    assert state.key?(:current_nominator_id)
    assert state.key?(:current_turn_started_at)
    assert state.key?(:nomination_picks_remaining)
    assert state.key?(:tiebreak)
    assert_not state.key?(:current_nomination)

    assert_equal 1, state[:candidates].size
    state[:candidates].first["voters"].each { |v| assert_kind_of String, v }
  end

  test "voter ids are stored as integers in state_data" do
    # Server stores integers in state_data; only stringifies for the
    # broadcast payload. Reviewer focus area #6 (integer storage).
    move_to_nominating!
    nominator = @draft.current_nominator_id
    @draft.nominate!(nominator, @groups[4].id)
    @draft.reload
    voters = @draft.candidates.first["voters"]
    voters.each { |v| assert_kind_of Integer, v }
  end

  private

  def move_to_voting!
    ALL_PLAYERS.each { |uid| @draft.mark_ready!(uid) }
    @draft.reload
  end

  def move_to_drafting!(first_picker:)
    move_to_voting!
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
