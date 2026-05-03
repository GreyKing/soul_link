module SoulLink
  # Side-effect handler for SaveDiff results. Called from
  # `SoulLink::ParseSaveDataJob` after the parsed_* columns are written.
  # Builds the SaveDiff and fans out to the per-category coordinators.
  #
  # Owns the baseline rule (skip dispatch on first-ever parse) and the
  # empty-diff short-circuit. ParseSaveDataJob stays a "pure parser +
  # persist" job — no per-category branching lives in it.
  #
  # Step 16 introduces this dispatcher to keep the job a thin facade as
  # we add categories. Step 15's existing dispatch logic relocates here
  # with no behavior change to badge handling.
  class SaveDiffDispatcher
    # @param slot [SoulLinkEmulatorSaveSlot] the slot whose parse just
    #   produced new parsed_* values.
    # @param prev [Hash] pre-parse snapshot of the slot's parsed_*
    #   columns. Required keys: :parsed_at, :badges, :trainer_id,
    #   :secret_id, :pokedex_caught, :pokedex_seen, :hof_count.
    # @param curr [Hash] post-parse snapshot — same shape.
    def self.dispatch(slot, prev:, curr:)
      # Baseline rule (Step 15): a slot's first-ever successful parse
      # has no prior baseline to diff against, so importing a save with
      # N badges does NOT fire N gym-beaten events. Same logic now
      # gates every category.
      return if prev[:parsed_at].nil?

      diff = SoulLink::SaveDiff.between(
        prev_badges:         prev[:badges],         curr_badges:         curr[:badges],
        prev_tid:            prev[:trainer_id],     curr_tid:            curr[:trainer_id],
        prev_sid:            prev[:secret_id],      curr_sid:            curr[:secret_id],
        prev_pokedex_caught: prev[:pokedex_caught], curr_pokedex_caught: curr[:pokedex_caught],
        prev_pokedex_seen:   prev[:pokedex_seen],   curr_pokedex_seen:   curr[:pokedex_seen],
        prev_hof_count:      prev[:hof_count],      curr_hof_count:      curr[:hof_count]
      )
      return if diff.empty?

      SoulLink::GymBeatenCoordinator.process(slot, diff.badge_events)         if diff.badge_events.any?
      SoulLink::TidObservationCoordinator.process(slot, diff.tid_events)      if diff.tid_events.any?
      SoulLink::PokedexProgressCoordinator.process(slot, diff.pokedex_events) if diff.pokedex_events.any?
      SoulLink::HallOfFameCoordinator.process(slot, diff.hof_events)          if diff.hof_events.any?
    end
  end
end
