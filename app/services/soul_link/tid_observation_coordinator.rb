module SoulLink
  # Log-only coordinator for `SoulLink::SaveDiff::TidObserved` events.
  #
  # No DB side effects — the user-visible value comes from the parser
  # persisting `parsed_trainer_id` / `parsed_secret_id` and the views
  # reading them. This coordinator exists for symmetric pattern
  # adherence and traceability — same shape as
  # `GymBeatenCoordinator`'s `BadgeLost` no-op log handler.
  #
  # TID-mix-up detection is read-side: see
  # `SoulLinkRun#tid_conflict_groups` which the dashboard uses to
  # surface a "⚠ TID conflict" pill on each affected save-slot card.
  class TidObservationCoordinator
    def self.process(slot, events)
      return if events.empty?
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil?

      events.each do |event|
        Rails.logger.info(
          "TidObservationCoordinator: TID=#{event.trainer_id} SID=#{event.secret_id} " \
          "run=#{run.id} session=#{slot.soul_link_emulator_session_id} slot=#{slot.id}"
        )
      end
    end
  end
end
