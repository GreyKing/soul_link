module SoulLink
  # Consumes `SaveDiff::BadgeGained` / `BadgeLost` events for a single
  # save-slot parse and decides whether to auto-mark a gym beaten on
  # the owning run.
  #
  # The all-4 AND-gate is the core of the policy: a gym auto-marks
  # only when *every* emulator session in the run has
  # `parsed_badges >= gym_number` on its currently-active slot. While
  # 1-3 players have the badge: the gym stays in its current state.
  # No partial UI signal in scope — the manual MARK BEATEN button
  # remains the sole bypass. See Step 15 brief Layer B for the full
  # rationale.
  #
  # Pure-static service (no AR ancestry, no instance state). Same
  # shape as `SoulLink::SaveParser`. Side effects (DB writes, log
  # lines) live here, not in `SaveDiff`.
  class GymBeatenCoordinator
    # Process the events emitted by `SaveDiff.between` for a single
    # slot. BadgeGained events run through the all-4 gate; BadgeLost
    # events are no-ops (logged at info level for traceability —
    # loading an older save state is normal user behavior).
    #
    # @param slot [SoulLinkEmulatorSaveSlot] the slot whose parse
    #   just produced events.
    # @param events [Array<SoulLink::SaveDiff::BadgeGained, SoulLink::SaveDiff::BadgeLost>]
    #   the diff payload from `SoulLink::SaveDiff.between`.
    def self.process(slot, events)
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil? || !run.active?

      events.each do |event|
        case event
        when SoulLink::SaveDiff::BadgeGained
          attempt_auto_mark(run, event.gym_number)
        when SoulLink::SaveDiff::BadgeLost
          Rails.logger.info(
            "GymBeatenCoordinator: BadgeLost gym_number=#{event.gym_number} " \
            "run=#{run.id} session=#{slot.soul_link_emulator_session_id} — no auto-unmark"
          )
        end
      end
    end

    # Three guards in priority order:
    #   1. idempotency — `gym_results` already exists, no-op
    #   2. suppression — manual UNMARK created a suppression row, no-op
    #   3. all-4 AND-gate — every session's active slot has the badge
    # Each early-returns silently. The create + counter bump are
    # wrapped in a single AR transaction so a stale `gyms_defeated`
    # update can't leave a half-applied state behind.
    def self.attempt_auto_mark(run, gym_number)
      return if run.gym_results.exists?(gym_number: gym_number)
      return if run.gym_auto_mark_suppressions.exists?(gym_number: gym_number)
      return unless all_players_have_badge?(run, gym_number)

      run.transaction do
        run.gym_results.create!(gym_number: gym_number, beaten_at: Time.current)
        run.update!(gyms_defeated: [ run.gyms_defeated, gym_number ].max)
      end
    end

    # All-4 check. Counts every session in the run (even if a player
    # hasn't generated their ROM yet — that session won't have an
    # `active_slot` and the `nil&.parsed_badges.to_i` chain returns 0,
    # which fails `>= gym_number` cleanly). Returns false on an empty
    # session set so a partially-onboarded run never spuriously marks
    # a gym.
    def self.all_players_have_badge?(run, gym_number)
      sessions = run.soul_link_emulator_sessions.includes(:save_slots)
      return false if sessions.empty?
      sessions.all? { |s| s.active_slot&.parsed_badges.to_i >= gym_number }
    end
  end
end
