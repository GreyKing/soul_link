class GymDraft < ApplicationRecord
  belongs_to :soul_link_run

  validates :status, inclusion: { in: %w[lobby voting drafting nominating complete] }

  STATUSES = %w[lobby voting drafting nominating complete].freeze
  TOTAL_SLOTS = 6
  INDIVIDUAL_ROUNDS = 4
  NOMINATION_ROUNDS = 2

  after_initialize :set_defaults, if: :new_record?

  # ── State Helpers ──

  def lobby?() = status == "lobby"
  def voting?() = status == "voting"
  def drafting?() = status == "drafting"
  def nominating?() = status == "nominating"
  def complete?() = status == "complete"

  def data
    (state_data || {}).with_indifferent_access
  end

  def ready_players
    data["ready_players"] || []
  end

  def first_pick_votes
    data["first_pick_votes"] || {}
  end

  def picks
    data["picks"] || []
  end

  def current_nomination
    data["current_nomination"]
  end

  def final_team_group_ids
    picks.map { |p| p["group_id"] }
  end

  # ── Player Helpers ──

  def players
    SoulLink::GameState.players
  end

  def player_ids
    SoulLink::GameState.player_ids
  end

  def all_players_ready?
    (player_ids - ready_players.map(&:to_i)).empty?
  end

  def all_voted?
    (player_ids - first_pick_votes.keys.map(&:to_i)).empty?
  end

  def current_drafter_id
    return nil unless drafting? && pick_order.present?
    pick_order[current_player_index]
  end

  # ── Actions ──

  def mark_ready!(uid)
    raise "Not in lobby" unless lobby?
    rp = ready_players
    rp << uid.to_i unless rp.include?(uid.to_i)
    update_data!("ready_players" => rp)

    if all_players_ready?
      update!(status: "voting")
    end
  end

  def cast_vote!(voter_uid, voted_for_uid)
    raise "Not in voting phase" unless voting?
    votes = first_pick_votes
    votes[voter_uid.to_s] = voted_for_uid.to_i
    update_data!("first_pick_votes" => votes)

    if all_voted?
      resolve_votes!
    end
  end

  def make_pick!(picker_uid, group_id)
    raise "Not in drafting phase" unless drafting?
    raise "Not your turn" unless current_drafter_id == picker_uid.to_i
    raise "That pokemon has already been picked" if picks.any? { |p| p["group_id"] == group_id.to_i }

    new_picks = picks + [{ "round" => picks.size + 1, "group_id" => group_id.to_i, "picked_by" => picker_uid.to_i }]
    next_index = current_player_index + 1

    if new_picks.size >= INDIVIDUAL_ROUNDS
      # All individual picks done — move to nomination
      update!(
        current_round: new_picks.size,
        current_player_index: 0,
        status: "nominating",
        state_data: data.merge("picks" => new_picks).as_json
      )
    else
      update!(
        current_round: new_picks.size,
        current_player_index: next_index,
        state_data: data.merge("picks" => new_picks).as_json
      )
    end
  end

  def submit_nomination!(nominator_uid, group_id)
    raise "Not in nominating phase" unless nominating?
    raise "Not your turn to nominate" unless pick_order[current_player_index % pick_order.size] == nominator_uid.to_i
    raise "Already have a pending nomination" if current_nomination.present?
    raise "That pokemon has already been picked" if picks.any? { |p| p["group_id"] == group_id.to_i }

    nomination = {
      "nominator_id" => nominator_uid.to_i,
      "group_id" => group_id.to_i,
      "votes" => { nominator_uid.to_s => true }
    }
    update_data!("current_nomination" => nomination)
  end

  def skip_turn!
    raise "Can only skip during drafting or nominating" unless drafting? || nominating?

    if drafting?
      next_index = current_player_index + 1
      if next_index >= pick_order.size
        # All players had a turn this round (some skipped) — move to nominating
        update!(
          current_player_index: 0,
          status: "nominating"
        )
      else
        update!(current_player_index: next_index)
      end
    else
      # Nominating phase
      next_index = (current_player_index + 1) % pick_order.size
      update!(
        current_player_index: next_index,
        state_data: data.merge("current_nomination" => nil).as_json
      )
    end
  end

  def vote_on_nomination!(voter_uid, approve)
    raise "Not in nominating phase" unless nominating?
    raise "No pending nomination" unless current_nomination.present?

    nom = current_nomination.deep_dup
    nom["votes"][voter_uid.to_s] = approve
    update_data!("current_nomination" => nom)

    # Check if all other players have voted
    other_ids = player_ids.map(&:to_s) - [nom["nominator_id"].to_s]
    all_voted = other_ids.all? { |id| nom["votes"].key?(id) }

    if all_voted
      resolve_nomination!
    end
  end

  # ── Serialized State ──

  def broadcast_state
    {
      id: id,
      status: status,
      current_round: current_round,
      current_player_index: current_player_index,
      pick_order: pick_order&.map(&:to_s),
      ready_players: ready_players.map(&:to_s),
      first_pick_votes: first_pick_votes.transform_values { |v| v.to_s },
      picks: picks.map { |p| p.merge("picked_by" => p["picked_by"].to_s) },
      current_nomination: current_nomination&.then { |n|
        n.merge("nominator_id" => n["nominator_id"].to_s)
      },
      current_drafter_id: current_drafter_id&.to_s,
      players: players.map { |p| p.merge("discord_user_id" => p["discord_user_id"].to_s) },
      player_ids: player_ids.map(&:to_s),
      final_team_group_ids: final_team_group_ids
    }
  end

  private

  def set_defaults
    self.state_data ||= { "ready_players" => [], "first_pick_votes" => {}, "picks" => [] }
    self.pick_order ||= []
  end

  def update_data!(changes)
    update!(state_data: data.merge(changes).as_json)
  end

  def resolve_votes!
    votes = first_pick_votes
    tally = votes.values.tally

    # Find max votes
    max_count = tally.values.max
    winners = tally.select { |_, count| count == max_count }.keys

    # Random tiebreak
    first_pick = winners.sample

    # Build pick order: winner first, rest in settings.yml order
    remaining = player_ids.reject { |id| id == first_pick }
    order = [first_pick] + remaining

    update!(
      status: "drafting",
      pick_order: order,
      current_round: 0,
      current_player_index: 0
    )
  end

  def resolve_nomination!
    nom = current_nomination
    other_ids = player_ids.map(&:to_s) - [nom["nominator_id"].to_s]
    approvals = other_ids.count { |id| nom["votes"][id] == true }
    # Majority of others (2+ out of 3)
    approved = approvals >= (other_ids.size / 2.0).ceil

    if approved
      new_picks = picks + [{
        "round" => picks.size + 1,
        "group_id" => nom["group_id"],
        "picked_by" => nom["nominator_id"]
      }]
      next_nominator_index = (current_player_index + 1) % pick_order.size

      if new_picks.size >= TOTAL_SLOTS
        # Draft complete
        update!(
          status: "complete",
          current_round: new_picks.size,
          current_player_index: next_nominator_index,
          state_data: data.merge("picks" => new_picks, "current_nomination" => nil).as_json
        )
      else
        update!(
          current_round: new_picks.size,
          current_player_index: next_nominator_index,
          state_data: data.merge("picks" => new_picks, "current_nomination" => nil).as_json
        )
      end
    else
      # Rejected — clear nomination
      update_data!("current_nomination" => nil)
    end
  end
end
