module SoulLink
  # Pure function that compares two snapshots of a save slot's parsed
  # state and returns the structured diff events the auto-tracking
  # coordinators consume.
  #
  # **Contract: zero side effects.** No `Rails.logger`, no AR, no
  # `Time.current`. Pure integer arithmetic on the inputs. The
  # coordinators (one per category) own all observable behavior.
  #
  # Step 15 shipped only the badge dimension. Step 16 extends the
  # `Result` struct with three new dimensions:
  #   - `tid_events:`     — TID/SID transitions (TidObserved)
  #   - `pokedex_events:` — Pokédex caught/seen deltas (PokedexProgress)
  #   - `hof_events:`     — Hall of Fame entry transitions (HallOfFameEntered)
  #
  # New keyword fields default to `[]` so Step-15-style callers using
  # only `prev_badges:` / `curr_badges:` continue working unchanged.
  module SaveDiff
    BadgeGained       = Struct.new(:gym_number, keyword_init: true)
    BadgeLost         = Struct.new(:gym_number, keyword_init: true)

    # Step 16 events.
    TidObserved       = Struct.new(:trainer_id, :secret_id, keyword_init: true)
    PokedexProgress   = Struct.new(:caught_delta, :seen_delta, :curr_caught, :curr_seen, keyword_init: true)
    HallOfFameEntered = Struct.new(:hof_count, keyword_init: true)

    # Step 17: party-block events for catches + routes auto-detection.
    #
    # Pkm is a value-object representation of a single party slot's
    # decrypted data — same fields as `SoulLink::PkmDecoder::Pkm` but
    # re-declared here so callers don't have to reach across the
    # decryption layer to use the diff layer in isolation. Values
    # arrive as plain Ruby Hashes (the dispatcher serializes the
    # PkmDecoder structs through JSON when persisting `parsed_party_data`,
    # so on the read-back side they're already Hash-shaped).
    #
    # Diff key = PID (uint32, the encryption seed). New PIDs in curr_party
    # → PokemonCaughtEvent. PIDs in prev_party but not curr_party →
    # PokemonRemovedEvent. Same PID present in both → no event (covers
    # deposit-and-re-catch round-trip across the box block which we
    # don't parse in Step 17).
    PokemonCaughtEvent  = Struct.new(
      :pid, :species_id, :met_location_id, :level, :ot_id, :ot_sid, :is_egg,
      keyword_init: true
    )
    PokemonRemovedEvent = Struct.new(:pid, keyword_init: true)

    Result = Struct.new(
      :badge_events, :tid_events, :pokedex_events, :hof_events,
      :catch_events, :removal_events,
      keyword_init: true
    ) do
      def empty?
        badge_events.empty? && tid_events.empty? &&
          pokedex_events.empty? && hof_events.empty? &&
          catch_events.empty? && removal_events.empty?
      end
    end

    # Compares two snapshots and emits per-category events. All event
    # arrays are always present in the Result (default `[]`) so callers
    # can iterate them unconditionally.
    #
    # Backward-compat: a Step-15-style `SaveDiff.between(prev_badges: 0,
    # curr_badges: 1)` call returns
    # `Result.new(badge_events: [BadgeGained.new(gym_number: 1)],
    #             tid_events: [], pokedex_events: [], hof_events: [])`.
    #
    # @param prev_badges, curr_badges [Integer, nil] — Step 15 contract.
    #   Nil on either side → no badge events (first parse / parse-fail).
    # @param prev_tid, curr_tid, prev_sid, curr_sid [Integer, nil] —
    #   uint16 trainer / secret IDs. Step 16 TidObserved fires on a
    #   transition where curr is present-and-nonzero (zero is treated
    #   as "unset / not parsed yet" and never produces an event).
    # @param prev_pokedex_caught, curr_pokedex_caught [Integer, nil]
    # @param prev_pokedex_seen,   curr_pokedex_seen   [Integer, nil] —
    #   popcounts of the caught/seen regions. PokedexProgress fires on
    #   any change in either; deltas may be negative (older save load).
    #   Skip if either snapshot side is nil (defensive — first parse /
    #   parse failure are normally short-circuited upstream).
    # @param prev_hof_count, curr_hof_count [Integer, nil] — HoF
    #   ClearCount. HallOfFameEntered fires only on the
    #   prev-was-nil-or-zero → curr-≥-1 transition. Subsequent
    #   increments (1 → 2) are not interesting at the diff level.
    #   Skip if curr is nil.
    def self.between(prev_badges:, curr_badges:,
                     prev_tid: nil, curr_tid: nil,
                     prev_sid: nil, curr_sid: nil,
                     prev_pokedex_caught: nil, curr_pokedex_caught: nil,
                     prev_pokedex_seen: nil,   curr_pokedex_seen: nil,
                     prev_hof_count: nil,      curr_hof_count: nil,
                     prev_party: nil,          curr_party: nil)
      catches, removals = diff_party(prev_party, curr_party)
      Result.new(
        badge_events:   diff_badges(prev_badges, curr_badges),
        tid_events:     diff_tid(prev_tid, prev_sid, curr_tid, curr_sid),
        pokedex_events: diff_pokedex(prev_pokedex_caught, curr_pokedex_caught,
                                     prev_pokedex_seen,   curr_pokedex_seen),
        hof_events:     diff_hof(prev_hof_count, curr_hof_count),
        catch_events:   catches,
        removal_events: removals
      )
    end

    # ── per-dimension helpers ─────────────────────────────────────────

    # Step 15 logic preserved verbatim — multi-bit jumps emit one event
    # per gym in sequential order so each runs through the all-4 gate
    # in `GymBeatenCoordinator` independently.
    def self.diff_badges(prev_badges, curr_badges)
      events = []
      return events if prev_badges.nil? || curr_badges.nil? || prev_badges == curr_badges
      if curr_badges > prev_badges
        ((prev_badges + 1)..curr_badges).each { |n| events << BadgeGained.new(gym_number: n) }
      else
        ((curr_badges + 1)..prev_badges).each { |n| events << BadgeLost.new(gym_number: n) }
      end
      events
    end

    def self.diff_tid(prev_tid, prev_sid, curr_tid, curr_sid)
      # Skip when curr is unset/zero (the slot just hasn't been parsed
      # yet, or the parser returned 0 for a missing slice).
      return [] if curr_tid.nil? || curr_tid.to_i.zero?
      return [] if [ prev_tid, prev_sid ] == [ curr_tid, curr_sid ]
      [ TidObserved.new(trainer_id: curr_tid, secret_id: curr_sid) ]
    end

    def self.diff_pokedex(prev_caught, curr_caught, prev_seen, curr_seen)
      # Defensive: both sides must be present. The first-parse and
      # parse-failure paths are short-circuited upstream by the
      # dispatcher's baseline rule, but we still guard here so
      # SaveDiff.between is safe to call in isolation.
      return [] if prev_caught.nil? || curr_caught.nil? || prev_seen.nil? || curr_seen.nil?
      return [] if prev_caught == curr_caught && prev_seen == curr_seen
      [
        PokedexProgress.new(
          caught_delta: curr_caught - prev_caught,
          seen_delta:   curr_seen   - prev_seen,
          curr_caught:  curr_caught,
          curr_seen:    curr_seen
        )
      ]
    end

    def self.diff_hof(prev_hof, curr_hof)
      return [] if curr_hof.nil?
      return [] unless curr_hof >= 1
      # Only the 0/nil → ≥1 transition is interesting. Subsequent
      # increments (1 → 2 → 3) are repeat clears, not run-completion
      # signals.
      return [] if !prev_hof.nil? && prev_hof >= 1
      [ HallOfFameEntered.new(hof_count: curr_hof) ]
    end

    # Step 17: party diff. Returns [catches, removals].
    #
    # Both inputs are Array<Hash> (or nil). Each entry has keys :pid,
    # :species (or :species_id), :met_location_id, :level, :ot_id,
    # :ot_sid, :is_egg — the JSON serialization of a `PkmDecoder::Pkm`
    # value object plus whatever else `parsed_party_data` happens to
    # carry. Both string keys and symbol keys are accepted (HashWithIndifferentAccess
    # would also work; we coerce via `&.[]` calls).
    #
    # Defensive: if either side is nil, returns [[], []] (e.g. first
    # parse with prev_party still null, or PartyParser returned nil for
    # the curr side because the save was unparseable). The dispatcher's
    # baseline rule already filters first-ever parses; this guard is
    # defense in depth so SaveDiff.between is safe in isolation.
    def self.diff_party(prev_party, curr_party)
      return [ [], [] ] if prev_party.nil? || curr_party.nil?

      prev_by_pid = index_party_by_pid(prev_party)
      curr_by_pid = index_party_by_pid(curr_party)

      catches = []
      curr_by_pid.each do |pid, entry|
        next if prev_by_pid.key?(pid)
        catches << PokemonCaughtEvent.new(
          pid:             pid,
          species_id:      hash_get(entry, :species_id) || hash_get(entry, :species),
          met_location_id: hash_get(entry, :met_location_id),
          level:           hash_get(entry, :level),
          ot_id:           hash_get(entry, :ot_id),
          ot_sid:          hash_get(entry, :ot_sid),
          is_egg:          hash_get(entry, :is_egg) ? true : false
        )
      end

      removals = []
      prev_by_pid.each_key do |pid|
        next if curr_by_pid.key?(pid)
        removals << PokemonRemovedEvent.new(pid: pid)
      end

      [ catches, removals ]
    end

    # Build a {pid => entry} index. Skips entries with nil/zero PID
    # (defensive — a corrupt PKM that survived earlier filters
    # shouldn't show up as a catch event).
    def self.index_party_by_pid(party)
      result = {}
      Array(party).each do |entry|
        pid = hash_get(entry, :pid).to_i
        next if pid.zero?
        result[pid] = entry
      end
      result
    end

    # Look up a key in a Hash that may be string-keyed (from JSON load)
    # or symbol-keyed (from a Ruby caller). Returns nil if absent or
    # if `entry` isn't a Hash.
    def self.hash_get(entry, key)
      return nil unless entry.is_a?(Hash)
      entry[key] || entry[key.to_s]
    end
  end
end
