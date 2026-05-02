require "test_helper"

class GymDraftChannelTest < ActionCable::Channel::TestCase
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
    stub_connection(current_user_id: GREY)
  end

  test "subscribes and streams for draft" do
    subscribe(draft_id: @draft.id)
    assert subscription.confirmed?
    assert_has_stream_for @draft
  end

  test "subscribes and broadcasts initial state" do
    assert_broadcasts(@draft, 1) do
      subscribe(draft_id: @draft.id)
    end
  end

  test "ready action marks player ready" do
    subscribe(draft_id: @draft.id)
    perform :ready
    @draft.reload
    assert_includes @draft.ready_players, GREY
  end

  test "ready action broadcasts state update" do
    subscribe(draft_id: @draft.id)
    assert_broadcasts(@draft, 1) do
      perform :ready
    end
  end

  test "vote action records vote" do
    move_to_voting!
    subscribe(draft_id: @draft.id)
    perform :vote, { "voted_for" => ARATY }
    @draft.reload
    assert_equal ARATY, @draft.first_pick_votes[GREY.to_s]
  end

  test "pick action records pick in drafting phase" do
    move_to_drafting!(first_picker: GREY)
    subscribe(draft_id: @draft.id)
    perform :pick, { "group_id" => @groups[0].id }
    @draft.reload
    assert_equal 1, @draft.picks.size
    assert_equal @groups[0].id, @draft.picks.first["group_id"]
  end

  # ── Step 14: unified nominate-or-endorse ──

  test "nominate action creates a new candidate" do
    move_to_nominating!(first_nominator: GREY)
    subscribe(draft_id: @draft.id)
    perform :nominate, { "group_id" => @groups[4].id }
    @draft.reload
    assert_equal 1, @draft.candidates.size
    assert_equal @groups[4].id, @draft.candidates.first["group_id"]
    assert_equal [ GREY ], @draft.candidates.first["voters"]
  end

  test "nominate action endorses an existing candidate" do
    move_to_nominating!(first_nominator: GREY)
    # Grey nominates first
    @draft.nominate!(GREY, @groups[4].id)
    @draft.reload
    # Whoever is up next endorses through the channel — restub the
    # connection to that player's user id.
    next_nominator = @draft.current_nominator_id
    stub_connection(current_user_id: next_nominator)
    subscribe(draft_id: @draft.id)
    perform :nominate, { "group_id" => @groups[4].id }
    @draft.reload
    assert_equal 1, @draft.candidates.size
    assert_equal [ GREY, next_nominator ], @draft.candidates.first["voters"]
  end

  test "skip rejected for non-nominator before grace" do
    move_to_nominating!(first_nominator: ARATY)
    # Connection is GREY, nominator is ARATY, no time elapsed.
    subscribe(draft_id: @draft.id)
    perform :skip
    assert_match(/Not your turn/, transmissions.last["error"])
  end

  test "skip allowed for non-nominator after grace" do
    move_to_nominating!(first_nominator: ARATY)
    subscribe(draft_id: @draft.id)
    travel 65.seconds do
      before_index = @draft.reload.current_player_index
      perform :skip
      @draft.reload
      assert_not_equal before_index, @draft.current_player_index
    end
  end

  test "vote_nomination action no longer exists" do
    # Step 14 removed `vote_nomination` entirely. ActionCable's
    # ChannelTest will silently no-op on a missing action (security
    # belt — it's actually `action_methods` that gates dispatch), so
    # we assert against the source of truth: the channel class no
    # longer responds to that action and the model accessor is gone.
    assert_not_includes GymDraftChannel.action_methods, "vote_nomination"
    refute_respond_to @draft, :submit_nomination!
    refute_respond_to @draft, :vote_on_nomination!
    refute_respond_to @draft, :resolve_nomination!
    refute_respond_to @draft, :current_nomination
  end

  test "wrong phase action transmits error" do
    subscribe(draft_id: @draft.id)
    # Try to vote in lobby phase — should transmit error
    perform :vote, { "voted_for" => ARATY }
    assert_equal({ "error" => "Not in voting phase" }, transmissions.last)
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

  def move_to_nominating!(first_nominator: GREY)
    move_to_drafting!(first_picker: first_nominator)
    pick_order = @draft.pick_order
    4.times do |i|
      picker = pick_order[i]
      @draft.reload
      @draft.make_pick!(picker, @groups[i].id)
    end
    @draft.reload
  end
end
