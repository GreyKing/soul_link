module SoulLink
  # Log-only coordinator for `SoulLink::SaveDiff::PokedexProgress` events.
  #
  # No DB side effects — the user-visible value comes from the parser
  # persisting `parsed_pokedex_caught` / `parsed_pokedex_seen` and the
  # views reading them. This coordinator exists for symmetric pattern
  # adherence and traceability — same shape as
  # `TidObservationCoordinator`.
  class PokedexProgressCoordinator
    def self.process(slot, events)
      return if events.empty?
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil?

      events.each do |event|
        Rails.logger.info(
          "PokedexProgressCoordinator: caught Δ#{event.caught_delta} (now #{event.curr_caught}) " \
          "seen Δ#{event.seen_delta} (now #{event.curr_seen}) " \
          "run=#{run.id} session=#{slot.soul_link_emulator_session_id} slot=#{slot.id}"
        )
      end
    end
  end
end
