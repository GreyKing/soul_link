class AddGuildIdToSoulLinkRuns < ActiveRecord::Migration[7.0]
  def change
    # Add guild_id with a default to backfill existing rows with the original server
    add_column :soul_link_runs, :guild_id, :bigint, null: false, default: 404132250385383433

    # Remove the default so future rows must explicitly provide guild_id
    change_column_default :soul_link_runs, :guild_id, from: 404132250385383433, to: nil

    # Replace the global run_number unique index with one scoped to guild
    remove_index :soul_link_runs, :run_number
    add_index :soul_link_runs, [:guild_id, :run_number], unique: true

    # Add index for the most common query: finding the active run for a guild
    add_index :soul_link_runs, [:guild_id, :active]
  end
end
