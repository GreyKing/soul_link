class AddStep17ColumnsToSoulLinkPokemon < ActiveRecord::Migration[8.1]
  # Step 17 — PKM-decryption catch+routes auto-detection. Six new columns
  # on `soul_link_pokemon` that auto-detected catches populate; manual
  # catches leave them nil for backward compat with the existing Catch
  # modal flow:
  #
  #   pid              bigint  — uint32 PID (encryption seed; primary identity for de-dup)
  #   met_location_id  integer — Block-B `MetLocation_PtHGSS` u16 (0..65535)
  #   ot_id            integer — Block-A trainer-id u16 (TID)
  #   ot_sid           integer — Block-A secret-id u16 (SID)
  #   trade_in         boolean — true iff (ot_id, ot_sid) differs from slot's parsed TID/SID
  #   acquired_via     string  — 'catch' / 'trade_in' / 'event_gift' (nil for manual catches)
  #
  # The `pid` column is `bigint` because the underlying value is u32 —
  # MySQL `int unsigned` would also work but Rails defaults `:integer`
  # to signed int4; bigint is the safe pick. The other ID columns are
  # plain :integer (4 bytes signed) to match Step 16's pattern — uint16
  # fits cleanly without `limit: 2` smallint risk.
  #
  # Validations stay backward-compatible: pid is nullable so existing
  # manual catches (Step 1+ Catch modal) continue to validate. All
  # additive — no defaults that backfill, no breaking changes.
  #
  # Compound index `(soul_link_run_id, discord_user_id, pid)` is
  # non-unique to keep the migration shape simple per brief decision 9
  # ("application-level uniqueness check is acceptable for v1"). The
  # `CatchCoordinator` checks `WHERE pid = ?` before insert, so the
  # index serves the dedup-lookup hot path.
  def change
    add_column :soul_link_pokemon, :pid,             :bigint
    add_column :soul_link_pokemon, :met_location_id, :integer
    add_column :soul_link_pokemon, :ot_id,           :integer
    add_column :soul_link_pokemon, :ot_sid,          :integer
    add_column :soul_link_pokemon, :trade_in,        :boolean, default: false, null: false
    add_column :soul_link_pokemon, :acquired_via,    :string

    add_index  :soul_link_pokemon,
               [ :soul_link_run_id, :discord_user_id, :pid ],
               name: "index_soul_link_pokemon_on_run_user_pid"
  end
end
