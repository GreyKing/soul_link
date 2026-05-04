class AddStep18ColumnsToSoulLinkPokemon < ActiveRecord::Migration[8.1]
  # Step 18 — per-Pokémon stats columns populated alongside Step 17's
  # auto-detected catches. The PkmDecoder now surfaces Nature, IVs, EVs,
  # and the moveset; CatchCoordinator persists them on create.
  #
  # Columns added here:
  #
  #   ivs              json    — { hp, atk, def, spe, spa, spd } each 0..31
  #   evs              json    — { hp, atk, def, spe, spa, spd } each 0..255
  #   moves            json    — Array of 4 { id, pp, pp_up } hashes
  #   caught_off_feed  boolean — true iff this row arrived via PC-box diff
  #                              (BoxedPokemonObservedEvent), false on the
  #                              party-side path. Defaults false at the DB
  #                              level so legacy Step-17 rows read as
  #                              false (correct semantics).
  #
  # `nature` (string) ALREADY EXISTS on this table from earlier work
  # (schema.rb:180 — the legacy 20260406000002 migration). The Step-18
  # decoder writes it via the same column; no re-add required.
  #
  # All additive, all nullable JSON. Step-17 rows continue to satisfy
  # validations (none of the new columns are validated against). The view
  # layer guards each field with `.present?`/`.is_a?(Hash|Array)` so
  # nil/null rows render cleanly.
  def change
    add_column :soul_link_pokemon, :ivs,             :json
    add_column :soul_link_pokemon, :evs,             :json
    add_column :soul_link_pokemon, :moves,           :json
    add_column :soul_link_pokemon, :caught_off_feed, :boolean, default: false, null: false
  end
end
