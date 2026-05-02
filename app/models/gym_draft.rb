class GymDraft < ApplicationRecord
  belongs_to :soul_link_run
  has_many :gym_results, dependent: :nullify

  validates :status, inclusion: { in: %w[lobby voting drafting nominating complete] }

  STATUSES = %w[lobby voting drafting nominating complete].freeze
  TOTAL_SLOTS = 6
  INDIVIDUAL_ROUNDS = 4
  NOMINATION_ROUNDS = 2
  # Step 14 unified the nominating phase to a single 4-pick "nominate or
  # endorse" pass. The grace window starts the moment a nominator's turn
  # begins; before it expires only that nominator can skip themselves,
  # after it any player can skip them.
  NOMINATION_GRACE_SECONDS = 60
  # How many slots the nominating phase fills (slots 5 and 6).
  NOMINATION_FINAL_SLOTS = 2

  after_initialize :set_defaults, if: :new_record?

  # ── State Helpers ──

  def lobby? = status == "lobby"
  def voting? = status == "voting"
  def drafting? = status == "drafting"
  def nominating? = status == "nominating"
  def complete? = status == "complete"

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

  # Candidates for the nominating phase. Each entry is
  # `{ "group_id" => Integer, "voters" => [Integer, ...] }`.
  # `voters[0]` is the nominator (the player who created the candidate);
  # subsequent voters are endorsers. List is append-only and stable.
  def candidates
    data["candidates"] || []
  end

  # Tiebreak payload populated by `resolve_nominations!` when the slot
  # boundary lands on a tie. Cleared (`nil`) when no tie occurred.
  def tiebreak
    data["tiebreak"]
  end

  # When did the current nominator's turn begin? Drives the 60-second
  # grace window for skip authorization.
  def current_turn_started_at
    ts = data["current_turn_started_at"]
    ts.present? ? Time.zone.parse(ts) : nil
  end

  # True when the current nominator's turn has been open for ≥60s, OR
  # when no `current_turn_started_at` is set (defensive default — better
  # to allow a skip than to lock the draft if state is malformed).
  def grace_elapsed?
    return true if current_turn_started_at.nil?
    Time.current - current_turn_started_at >= NOMINATION_GRACE_SECONDS
  end

  # The discord_user_id (Integer) whose turn it is to nominate, or nil
  # if not in the nominating phase. Wraps `current_player_index` against
  # `pick_order.size` so a skip past the end loops to the front.
  def current_nominator_id
    return nil unless nominating?
    pick_order[current_player_index % pick_order.size]
  end

  # How many of the 4 nominating-phase picks have been made so far. Each
  # candidate's voter list represents picks that landed on it; summing
  # the lists gives the total.
  def nomination_picks_made
    candidates.flat_map { |c| c["voters"] }.size
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

    new_picks = picks + [ { "round" => picks.size + 1, "group_id" => group_id.to_i, "picked_by" => picker_uid.to_i } ]
    next_index = current_player_index + 1

    if new_picks.size >= INDIVIDUAL_ROUNDS
      # All individual picks done — move to nomination. Seed the new
      # nominating-phase state shape: empty candidates list and the
      # turn-start timestamp that drives the 60s grace window.
      update!(
        current_round: new_picks.size,
        current_player_index: 0,
        status: "nominating",
        state_data: data.merge(
          "picks" => new_picks,
          "candidates" => [],
          "current_turn_started_at" => Time.current.iso8601,
          "tiebreak" => nil
        ).as_json
      )
    else
      update!(
        current_round: new_picks.size,
        current_player_index: next_index,
        state_data: data.merge("picks" => new_picks).as_json
      )
    end
  end

  # Unified nominate-or-endorse action. If `group_id` is already a
  # candidate, the picker is appended to that candidate's voter list;
  # otherwise a brand-new candidate is created with the picker as
  # nominator. After all 4 players have made their nominating-phase
  # pick, automatically resolves into the final 2 team slots.
  def nominate!(picker_uid, group_id)
    raise "Not in nominating phase" unless nominating?
    raise "Not your turn to nominate" unless current_nominator_id == picker_uid.to_i
    raise "That pokemon has already been picked" if picks.any? { |p| p["group_id"] == group_id.to_i }

    cands = candidates.map(&:deep_dup)
    existing = cands.find { |c| c["group_id"] == group_id.to_i }
    if existing
      raise "You already endorsed this nomination" if existing["voters"].include?(picker_uid.to_i)
      existing["voters"] << picker_uid.to_i
    else
      cands << { "group_id" => group_id.to_i, "voters" => [ picker_uid.to_i ] }
    end

    next_index = (current_player_index + 1) % pick_order.size
    total_picks_after = cands.flat_map { |c| c["voters"] }.size

    if total_picks_after >= pick_order.size
      # All 4 players have made their nominating-phase pick — persist
      # the final candidates list, clear the turn timer, and resolve.
      update!(
        state_data: data.merge(
          "candidates" => cands,
          "current_turn_started_at" => nil
        ).as_json
      )
      reload
      resolve_nominations!
    else
      update!(
        current_player_index: next_index,
        state_data: data.merge(
          "candidates" => cands,
          "current_turn_started_at" => Time.current.iso8601
        ).as_json
      )
    end
  end

  # Skip semantics:
  # - drafting: only the current drafter may skip themselves.
  # - nominating: the current nominator may always skip; any other
  #   player may skip after `NOMINATION_GRACE_SECONDS` have elapsed
  #   since the current nominator's turn began.
  def skip_turn!(requester_uid)
    raise "Can only skip during drafting or nominating" unless drafting? || nominating?

    if drafting?
      raise "Not your turn" unless current_drafter_id == requester_uid.to_i
      next_index = current_player_index + 1
      if next_index >= pick_order.size
        # All players had a turn this round (some skipped) — move to
        # nominating and seed the turn timer like make_pick! does.
        update!(
          current_player_index: 0,
          status: "nominating",
          state_data: data.merge(
            "candidates" => candidates,
            "current_turn_started_at" => Time.current.iso8601,
            "tiebreak" => nil
          ).as_json
        )
      else
        update!(current_player_index: next_index)
      end
    else
      # Nominating phase — auth: current nominator any time, OR any
      # player after the 60s grace expires.
      is_current = current_nominator_id == requester_uid.to_i
      raise "Not your turn (skip available to others after 60s)" unless is_current || grace_elapsed?

      next_index = (current_player_index + 1) % pick_order.size
      update!(
        current_player_index: next_index,
        state_data: data.merge("current_turn_started_at" => Time.current.iso8601).as_json
      )
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
      candidates: candidates.map { |c|
        { "group_id" => c["group_id"], "voters" => c["voters"].map(&:to_s) }
      },
      current_drafter_id: current_drafter_id&.to_s,
      current_nominator_id: current_nominator_id&.to_s,
      current_turn_started_at: data["current_turn_started_at"],
      nomination_picks_remaining: pick_order.present? ? pick_order.size - nomination_picks_made : 0,
      tiebreak: tiebreak,
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
    order = [ first_pick ] + remaining

    update!(
      status: "drafting",
      pick_order: order,
      current_round: 0,
      current_player_index: 0
    )
  end

  # Resolve the 4 nominating-phase picks into the final 2 team slots.
  # Greedy fill in voter-count-desc order:
  #   - if the next "same-count group" fits in remaining slots → take all.
  #   - otherwise the slot boundary lands on a tie → randomly select
  #     `remaining_slots` from the tied group and record `tiebreak`
  #     payload so the client can drive the coin-flip reveal.
  #
  # Edge cases handled:
  #   - 3/1 split → A wins slot 5, B wins slot 6, no tiebreak.
  #   - 2/2 split → both fill slots 5+6, no tiebreak.
  #   - 2/1/1 split → A fills slot 5; one of B/C fills slot 6 (tiebreak.type=second_place).
  #   - 1/1/1/1 split → all 4 tied, pick 2 randomly (tiebreak.type=n_way).
  #   - 1-candidate consensus (4/0) → only candidate fills slot 5;
  #     slot 6 stays empty; team is 5 strong by design.
  def resolve_nominations!
    cands = candidates
    # Sort by voter count desc; preserve nomination order as stable secondary.
    ranked = cands.each_with_index.sort_by { |c, i| [ -c["voters"].size, i ] }.map(&:first)

    winners = []
    tiebreak_payload = nil

    remaining_slots = NOMINATION_FINAL_SLOTS
    i = 0
    while i < ranked.size && remaining_slots > 0
      same_count_group = ranked[i..].take_while { |c| c["voters"].size == ranked[i]["voters"].size }
      if same_count_group.size <= remaining_slots
        winners.concat(same_count_group)
        remaining_slots -= same_count_group.size
        i += same_count_group.size
      else
        # Tie at the threshold — pick `remaining_slots` of `same_count_group` randomly.
        chosen = same_count_group.shuffle.first(remaining_slots)
        tiebreak_payload = {
          "type" => same_count_group.size == cands.size ? "n_way" : "second_place",
          "tied_group_ids" => same_count_group.map { |c| c["group_id"] },
          "winners" => chosen.map { |c| c["group_id"] }
        }
        winners.concat(chosen)
        remaining_slots = 0
      end
    end

    new_picks = picks.dup
    winners.each_with_index do |c, idx|
      new_picks << {
        "round" => picks.size + idx + 1,
        "group_id" => c["group_id"],
        "picked_by" => c["voters"].first  # nominator
      }
    end

    update!(
      status: "complete",
      current_round: new_picks.size,
      state_data: data.merge(
        "picks" => new_picks,
        "tiebreak" => tiebreak_payload
      ).as_json
    )
  end
end
