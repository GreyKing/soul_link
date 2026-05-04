class AddParsedBoxDataToSoulLinkEmulatorSaveSlots < ActiveRecord::Migration[8.1]
  # Step 18 — persist the BoxParser output JSON alongside Step 17's
  # `parsed_party_data`. Same shape: Array<Hash> where each entry is a
  # `PkmDecoder::Pkm` Struct's `to_h`. The next parse diff against this
  # column to emit `BoxedPokemonObservedEvent` for new PIDs in the box.
  #
  # KG-13 invariant preserved: `ParseSaveDataJob` only stamps
  # `parsed_at` on parse failure — `parsed_box_data` is left at its prior
  # value (or nil for first parse) to avoid spurious "all box mons
  # disappeared" diffs through the pipeline.
  def change
    add_column :soul_link_emulator_save_slots, :parsed_box_data, :json
  end
end
