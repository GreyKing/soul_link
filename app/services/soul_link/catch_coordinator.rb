module SoulLink
  # Side-effect coordinator for `SoulLink::SaveDiff::PokemonCaughtEvent`
  # / `PokemonRemovedEvent` events. Mirrors the shape of
  # `GymBeatenCoordinator` and `HallOfFameCoordinator`.
  #
  # PokemonCaughtEvent → creates a `SoulLinkPokemon` row scoped to the
  # session's owning run + the player's discord_user_id, with `pid`,
  # `met_location_id`, `ot_id`, `ot_sid`, `trade_in`, `acquired_via` set
  # from the event. **No partner-linking** in Step 17 —
  # `soul_link_pokemon_group_id` stays nil; the existing manual
  # 4-player Catch modal flow remains the only path that creates groups.
  # A future Step 18+ will handle pairing.
  #
  # PokemonRemovedEvent → log-only, no AR side effect (mirrors
  # `BadgeLost` no-op). A player can drop a Pokemon to the box, deposit
  # in daycare, release, or trade out — none of those are death events
  # in our model. Auto-marking-dead is explicit Step 17 out-of-scope.
  #
  # ── Filters & dedup logic ──────────────────────────────────────────
  #
  # 1. **Eggs.** `event.is_egg == true` → silently no-op. PartyParser
  #    already filters eggs from its output, so eggs shouldn't reach
  #    this coordinator in normal operation; the guard is defense in
  #    depth.
  # 2. **PID dedup.** A row with `(soul_link_run_id, discord_user_id, pid)`
  #    matching the event → no-op. Covers the deposit-and-re-catch
  #    round-trip across the box block (a Pokemon deposited and later
  #    withdrawn re-appears in the party with the same PID, which would
  #    otherwise look like a "new catch"). Application-level check
  #    backed by a non-unique compound index for lookup speed.
  # 3. **Trade-in detection.** When `event.ot_id` and/or `event.ot_sid`
  #    differ from the slot's `parsed_trainer_id` / `parsed_secret_id`,
  #    the row is created with `trade_in: true` AND
  #    `acquired_via: 'trade_in'`. The row IS still created (per brief
  #    decision 8 — surface trades, don't drop them).
  # 4. **Event-met filtering.** Met-location IDs flagged
  #    `event: true` in `met_locations.yml` (daycare, link trade,
  #    mystery gift, ranger, faraway-place sentinels) → row created
  #    with `acquired_via: 'event_gift'`. Players see the catch landed
  #    but can visually filter event-gifts vs. real catches.
  # 5. **Route name resolution.** `SoulLink::GameState.met_location_name`
  #    returns nil for unknown IDs; we fall back to "Met-Location ##{id}"
  #    (mirrors `EmulatorHelper#format_map_name`'s graceful-degradation
  #    pattern). Never raises.
  #
  # The whole `process` body is wrapped in a `slot.transaction { }` so a
  # raise mid-loop rolls back the partial creates (matches
  # `GymBeatenCoordinator.attempt_auto_mark`'s transaction semantics).
  class CatchCoordinator
    EVENT_GIFT_ACQUIRED   = "event_gift".freeze
    TRADE_IN_ACQUIRED     = "trade_in".freeze
    CATCH_ACQUIRED        = "catch".freeze

    def self.process(slot, events)
      return if events.nil? || events.empty?
      session = slot&.soul_link_emulator_session
      run = session&.soul_link_run
      return if run.nil?

      slot.transaction do
        events.each do |event|
          case event
          when SoulLink::SaveDiff::PokemonCaughtEvent
            handle_caught(slot, session, run, event)
          when SoulLink::SaveDiff::BoxedPokemonObservedEvent
            handle_box_observed(slot, session, run, event)
          when SoulLink::SaveDiff::PokemonRemovedEvent
            Rails.logger.info(
              "CatchCoordinator: PokemonRemovedEvent pid=#{event.pid} " \
              "run=#{run.id} session=#{session.id} — no auto-mark-dead"
            )
          end
        end
      end
    end

    def self.handle_caught(_slot, session, run, event)
      create_pokemon_row(session, run, event, caught_off_feed: false)
    end

    # Step 18 — `BoxedPokemonObservedEvent` arrives via the PC-box diff
    # path. Same shape as `handle_caught`; the only difference is the
    # `caught_off_feed: true` flag. The PID-dedup `.exists?` check
    # ensures a same-snapshot party+box double-fire creates only one
    # row, with the party-side `caught_off_feed: false` winning because
    # `SaveDiffDispatcher` orders catch_events ahead of box_events.
    def self.handle_box_observed(_slot, session, run, event)
      create_pokemon_row(session, run, event, caught_off_feed: true)
    end

    # Shared row-create path. Returns nil silently when the event is
    # filtered (egg / zero PID / unclaimed session / dedup hit) —
    # matching the prior `handle_caught` no-op semantics.
    def self.create_pokemon_row(session, run, event, caught_off_feed:)
      return if event.is_egg                  # defense-in-depth (filtered upstream)
      return if event.pid.to_i.zero?          # corrupt or empty slot

      uid = session.discord_user_id
      return if uid.nil?                      # session not yet claimed by a player

      # PID dedup against the (run, player, pid) triple. This single
      # check covers both intra-event-type dedup AND the cross-event
      # (party + box, same PID, same snapshot) collision — the
      # dispatcher orders catch_events first, so by the time a
      # BoxedPokemonObservedEvent for the same PID arrives the row is
      # already in DB and this exists? short-circuits.
      return if SoulLinkPokemon
                  .where(soul_link_run_id: run.id, discord_user_id: uid, pid: event.pid)
                  .exists?

      met_id    = event.met_location_id
      route     = resolve_route_name(met_id)
      species_s = resolve_species_string(event.species_id)
      trade_in  = trade_in?(session, event)
      via       = acquired_via(met_id, trade_in)
      nature_s  = SoulLink::Natures.name(event.nature) if event.nature

      SoulLinkPokemon.create!(
        soul_link_run_id:    run.id,
        discord_user_id:     uid,
        soul_link_pokemon_group_id: nil,    # Step-17 rows are unpaired
        species:             species_s,
        name:                species_s,
        location:            route,
        status:              "caught",
        level:               event.level,
        pid:                 event.pid,
        met_location_id:     met_id,
        ot_id:               event.ot_id,
        ot_sid:              event.ot_sid,
        trade_in:            trade_in,
        acquired_via:        via,
        # Step 18 — per-Pokémon stats. Nil for legacy parse data
        # (Step-17 parsed_party_data without the new keys); JSON
        # columns store nil cleanly.
        nature:              nature_s,
        ivs:                 event.ivs,
        evs:                 event.evs,
        moves:               event.moves,
        caught_off_feed:     caught_off_feed
      )
    end

    # Returns "Route 201" for known IDs; "Met-Location #N" fallback for
    # unknown ones; "Met-Location #?" for nil. Never raises.
    def self.resolve_route_name(met_id)
      name = SoulLink::GameState.met_location_name(met_id)
      return name if name.is_a?(String) && !name.empty?
      met_id.nil? ? "Met-Location #?" : "Met-Location ##{met_id}"
    end

    # Map species ID → species string. Soul Link's pokedex.yml is
    # name-keyed, so we have to invert it; the inverse is small enough
    # that a one-time sort is fine. Returns "Species #N" fallback for
    # unknown IDs (e.g. forms / event species not in our pokedex.yml).
    # NEVER nil — `SoulLinkPokemon.species` is `null: false` in DB.
    def self.resolve_species_string(species_id)
      sid = species_id.to_i
      name = species_name_by_id[sid]
      return name if name.is_a?(String) && !name.empty?
      "Species ##{sid.zero? ? '?' : sid}"
    end

    # Memoized species_id → name lookup. The pokedex.yml is keyed by
    # species name; we don't have a numeric-id source-of-truth, but
    # `pokemon_base_stats.national_dex_number` does — read from that AR
    # table as a runtime cache. (Pokedex.yml has no IDs at all; it's
    # purely a sprite-filename map.)
    def self.species_name_by_id
      @species_name_by_id ||= begin
        if defined?(PokemonBaseStat) && PokemonBaseStat.table_exists?
          PokemonBaseStat.pluck(:national_dex_number, :species).to_h
        else
          {}
        end
      rescue StandardError
        {}
      end
    end

    # Reset the memoized species lookup. Used in tests where the
    # pokemon_base_stats table is mutated between examples.
    def self.reset_species_cache!
      @species_name_by_id = nil
    end

    # Trade-in iff at least one of (TID, SID) differs from the slot's
    # parsed values. Both-nil event values (uninitialized) → false.
    # If the session hasn't parsed TID/SID yet (active_slot nil or
    # zero), we can't know — default to false (don't false-positive).
    def self.trade_in?(session, event)
      slot_tid = active_slot_tid(session)
      slot_sid = active_slot_sid(session)
      return false if slot_tid.to_i.zero? && slot_sid.to_i.zero?
      return false if event.ot_id.nil? && event.ot_sid.nil?

      event.ot_id.to_i != slot_tid.to_i || event.ot_sid.to_i != slot_sid.to_i
    end

    def self.active_slot_tid(session)
      session.active_slot&.parsed_trainer_id
    end

    def self.active_slot_sid(session)
      session.active_slot&.parsed_secret_id
    end

    def self.acquired_via(met_id, trade_in)
      return EVENT_GIFT_ACQUIRED if SoulLink::GameState.event_met_location?(met_id)
      return TRADE_IN_ACQUIRED   if trade_in
      CATCH_ACQUIRED
    end
  end
end
