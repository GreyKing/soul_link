require "test_helper"

class GymDraftChannelTest < ActionCable::Channel::TestCase
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

  test "nominate action creates nomination" do
    move_to_nominating!
    subscribe(draft_id: @draft.id)
    perform :nominate, { "group_id" => @groups[4].id }
    @draft.reload
    assert_equal @groups[4].id, @draft.current_nomination["group_id"]
  end

  test "vote_nomination action records vote" do
    move_to_nominating!
    @draft.submit_nomination!(ARATY, @groups[4].id)
    @draft.reload
    subscribe(draft_id: @draft.id)
    perform :vote_nomination, { "approve" => true }
    @draft.reload
    assert_equal true, @draft.current_nomination["votes"][GREY.to_s]
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
