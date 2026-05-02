module SoulLink
  # Parses the SRAM blob attached to a SoulLinkEmulatorSaveSlot (after every
  # slot create/update commit) and persists the surfaced trainer fields back
  # onto the slot row so the emulator-page slot column can render them
  # without doing parse work on every request.
  #
  # **KG-13 (closed Step 15):** on parse failure, ONLY `parsed_at` is
  # updated. The other `parsed_*` fields keep their prior values. This
  # prevents the previous behavior — zeroing `parsed_badges` on a
  # CRC-failed save — from producing spurious BadgeLost events through
  # the new `SaveDiff` pipeline when the next valid save lands.
  #
  # **Step 15 dispatch:** after writing the parse result, we capture the
  # pre-update `parsed_badges` and feed both values into
  # `SoulLink::SaveDiff.between`, then hand the events off to
  # `SoulLink::GymBeatenCoordinator`. The diff runs only when the slot
  # has a prior baseline (`prev_parsed_at.present?`) — the slot's first
  # ever successful parse is silent so importing a save with N badges
  # doesn't spam N gym-beaten events.
  #
  # **Critical**: writes via `update_columns` so the after_update_commit
  # callback that enqueued *this* job does not refire and create an
  # infinite loop. The parsed_* columns are derived data; no validations or
  # callbacks need to observe their writes.
  class ParseSaveDataJob < ApplicationJob
    queue_as :default

    def perform(slot)
      return if slot.nil?
      return if slot.save_data.blank?

      # Capture pre-update baseline BEFORE running the parse. Both
      # values must reflect the DB state from before this job's write
      # so the diff sees the actual transition.
      prev_parsed_at = slot.parsed_at
      prev_badges    = slot.parsed_badges

      result = SoulLink::SaveParser.parse(slot.save_data)

      if result
        slot.update_columns(
          parsed_trainer_name: result.trainer_name,
          parsed_money:        result.money,
          parsed_play_seconds: result.play_seconds,
          parsed_badges:       result.badges_count.to_i,
          parsed_map_id:       result.map_id,
          parsed_at:           Time.current
        )
      else
        # KG-13 fix: parse failed — only stamp parsed_at so we don't
        # re-loop. Leave every other parsed_* field at its prior value
        # so a CRC-bad save never appears as "lost all badges" to the
        # diff layer. The slot card still renders the most recently
        # successful parse.
        slot.update_columns(parsed_at: Time.current)
        return
      end

      # Diff dispatch. Skip on first-ever parse (baseline rule) so a
      # mid-run save import doesn't fire N events for a player who has
      # never had a parsed_at stamp before.
      return if prev_parsed_at.nil?

      diff = SoulLink::SaveDiff.between(
        prev_badges: prev_badges,
        curr_badges: result.badges_count.to_i
      )
      return if diff.empty?

      SoulLink::GymBeatenCoordinator.process(slot, diff.badge_events)
    end
  end
end
