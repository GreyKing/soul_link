class AddParsedPartyDataToSoulLinkEmulatorSaveSlots < ActiveRecord::Migration[8.1]
  # Step 17 — persist the PartyParser output JSON so the next parse has
  # a previous baseline to diff against. Same pattern as Step 16's
  # parsed_* columns: nullable, no default, populated by `update_columns`
  # in `ParseSaveDataJob` to avoid re-firing the after_update_commit
  # callback in a tight loop.
  #
  # JSON shape: Array<Hash> where each Hash carries {pid, species, level,
  # ot_id, ot_sid, met_location_id, met_level, is_egg, slot_index} —
  # the `Pkm` Struct's `to_h`. Empty array (`[]`) when the party block
  # is empty or the save is corrupt; nil when the parser hasn't yet
  # written this column (first-ever parse / pre-Step-17 rows).
  def change
    add_column :soul_link_emulator_save_slots, :parsed_party_data, :json
  end
end
