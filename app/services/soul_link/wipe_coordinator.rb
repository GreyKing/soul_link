module SoulLink
  # Step 19 — wipe-detection coordinator. Pure dispatch service (mirrors
  # `HallOfFameCoordinator`'s shape). Called from
  # `PokemonGroupsController#update` after `mark_as_dead!`.
  #
  # Wipe rule: a player has at least one catch in the run AND zero alive
  # Pokemon → the run is wiped. The Soul Link contract is "all 4 players
  # alive together"; the moment one player has no living Pokemon left,
  # the chain is broken. We pick the FIRST player (in
  # `SoulLink::GameState.player_ids` order) who satisfies the rule and
  # use their last dead Pokemon's location as the "wipe route" for the
  # notification.
  #
  # Idempotency: `run.wiped_at.present?` short-circuits at the top, AND
  # is double-checked inside `with_lock` to dodge the race where two
  # concurrent Mark Dead requests both pass the outer guard. Once
  # `wiped_at` is set, subsequent calls do nothing — including no second
  # Discord notification.
  #
  # NOT called on revive (caught→caught) — only after a `mark_as_dead!`
  # transition. The brief is explicit: "wipe coordinator runs whenever a
  # Pokémon's dead state changes (manual Mark Dead transition)."
  class WipeCoordinator
    def self.process(run)
      return if run.nil?
      return if run.wiped_at.present?

      uid, last_route = wiping_player_and_route(run)
      return if uid.nil?

      run.with_lock do
        # Double-check inside the lock — a concurrent Mark Dead may have
        # set `wiped_at` between the outer guard and this block.
        return if run.wiped_at.present?
        run.update!(wiped_at: Time.current)
      end

      SoulLink::DiscordNotifier.notify_wipe(run, uid, last_route)
      nil
    end

    # Walk registered players in canonical order; return the first
    # `[uid, last_route]` pair where the player has caught at least one
    # Pokemon in this run AND has zero alive. Returns `[nil, nil]` when
    # no player satisfies the rule (no wipe to fire).
    def self.wiping_player_and_route(run)
      SoulLink::GameState.player_ids.each do |uid|
        scope = run.soul_link_pokemon.where(discord_user_id: uid)
        next unless scope.exists?  # brand-new run / unclaimed player

        alive_count = scope.where(status: "caught").count
        next unless alive_count.zero?

        last_route = scope.where(status: "dead")
                          .order(died_at: :desc)
                          .first
                          &.location || "Unknown"
        return [ uid, last_route ]
      end
      [ nil, nil ]
    end
  end
end
