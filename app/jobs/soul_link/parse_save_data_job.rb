module SoulLink
  # Parses the SRAM blob attached to a SoulLinkEmulatorSaveSlot (after every
  # slot create/update commit) and persists the surfaced trainer fields back
  # onto the slot row so the emulator-page slot column can render them
  # without doing parse work on every request.
  #
  # On failure the parsed_* fields are nil-ed out (and parsed_at is still
  # set). The slot card renders "—" — that's the documented :failed path.
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

      result = SoulLink::SaveParser.parse(slot.save_data)

      attrs = if result
        {
          parsed_trainer_name: result.trainer_name,
          parsed_money:        result.money,
          parsed_play_seconds: result.play_seconds,
          parsed_badges:       result.badges_count.to_i,
          parsed_map_id:       result.map_id,
          parsed_at:           Time.current
        }
      else
        # Parse failed (corrupt SRAM, both slots invalid, etc.). Write nils
        # plus parsed_at so the slot card renders "—" and we don't loop.
        {
          parsed_trainer_name: nil,
          parsed_money:        nil,
          parsed_play_seconds: nil,
          parsed_badges:       0,
          parsed_map_id:       nil,
          parsed_at:           Time.current
        }
      end

      slot.update_columns(attrs)
    end
  end
end
