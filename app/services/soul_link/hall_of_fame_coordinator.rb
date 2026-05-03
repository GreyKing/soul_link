module SoulLink
  # Side-effect coordinator for `SoulLink::SaveDiff::HallOfFameEntered` events.
  #
  # When all 4 sessions in a run report `parsed_hof_count >= 1`, stamps
  # `run.completed_at = Time.current`. All-4 AND-gate, mirrors
  # `GymBeatenCoordinator.all_players_have_badge?`. Idempotent — skips
  # if `completed_at` is already set or if the run is inactive.
  #
  # The `active` flag is NOT auto-flipped. PO follow-on call (logged in
  # BUILD-LOG Known Gaps). The dashboard renders a "🏆 COMPLETE" pill
  # off `completed_at.present?`.
  #
  # No suppression table — once `completed_at` is set, the
  # `completed_at.present?` guard enforces idempotency. Direct AR
  # `update!(completed_at: nil)` is the un-completion path if PO ever
  # wants one.
  class HallOfFameCoordinator
    def self.process(slot, events)
      return if events.empty?
      run = slot.soul_link_emulator_session&.soul_link_run
      return if run.nil? || !run.active? || run.completed_at.present?
      return unless all_players_in_hall_of_fame?(run)

      run.update!(completed_at: Time.current)
      Rails.logger.info(
        "HallOfFameCoordinator: run=#{run.id} marked complete (4/4 HoF)"
      )
    end

    # All-4 check. Returns false on an empty session set so a
    # partially-onboarded run never spuriously marks complete (mirrors
    # `GymBeatenCoordinator.all_players_have_badge?`'s same guard).
    # `active_slot&.parsed_hof_count.to_i` chains nil-safe — a session
    # without an active slot, or with a slot that hasn't parsed HoF
    # yet, evaluates to 0 and fails the `>= 1` check correctly.
    def self.all_players_in_hall_of_fame?(run)
      sessions = run.soul_link_emulator_sessions.includes(:save_slots)
      return false if sessions.empty?
      sessions.all? { |s| s.active_slot&.parsed_hof_count.to_i >= 1 }
    end
  end
end
