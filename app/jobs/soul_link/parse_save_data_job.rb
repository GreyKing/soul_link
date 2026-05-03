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
  # **Step 16 dispatch:** the diff/dispatch logic (Step 15 introduced for
  # badges; Step 16 extends to TID/Pokédex/HoF) lives in
  # `SoulLink::SaveDiffDispatcher`. This job is now a "pure parser +
  # persist" — capture pre-update state, parse, persist, hand prev/curr
  # snapshots to the dispatcher. No per-category branching here.
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

      # Capture pre-update baseline BEFORE running the parse. Every
      # value reflects DB state from before this job's write so the
      # diff sees the actual transition.
      prev = capture_state(slot)

      result = SoulLink::SaveParser.parse(slot.save_data)

      if result
        slot.update_columns(
          parsed_trainer_name:   result.trainer_name,
          parsed_money:          result.money,
          parsed_play_seconds:   result.play_seconds,
          parsed_badges:         result.badges_count.to_i,
          parsed_map_id:         result.map_id,
          parsed_trainer_id:     result.trainer_id,
          parsed_secret_id:      result.secret_id,
          parsed_pokedex_caught: result.pokedex_caught,
          parsed_pokedex_seen:   result.pokedex_seen,
          parsed_hof_count:      result.hof_count,
          parsed_at:             Time.current
        )

        SoulLink::SaveDiffDispatcher.dispatch(slot, prev: prev, curr: capture_state(slot))
      else
        # KG-13 fix: parse failed — only stamp parsed_at so we don't
        # re-loop. Leave every other parsed_* field at its prior value
        # so a CRC-bad save never appears as "lost all badges" to the
        # diff layer. The slot card still renders the most recently
        # successful parse. Dispatch is skipped entirely (no Result).
        slot.update_columns(parsed_at: Time.current)
      end
    end

    private

    def capture_state(slot)
      {
        parsed_at:      slot.parsed_at,
        badges:         slot.parsed_badges,
        trainer_id:     slot.parsed_trainer_id,
        secret_id:      slot.parsed_secret_id,
        pokedex_caught: slot.parsed_pokedex_caught,
        pokedex_seen:   slot.parsed_pokedex_seen,
        hof_count:      slot.parsed_hof_count
      }
    end
  end
end
