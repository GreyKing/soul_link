class EnforceSingleActiveRunPerGuild < ActiveRecord::Migration[8.1]
  def up
    # Backfill check — abort if production data already violates the
    # invariant. The expectation is that this never trips in practice
    # (the `start_run` flow always deactivates the current run before
    # creating a new one), but raw DB tampering or a never-tested race
    # could have left dupes. Better to raise loudly than silently coerce
    # data the Project Owner hasn't decided what to do with.
    duplicate_guilds = SoulLinkRun.where(active: true)
                                  .group(:guild_id)
                                  .having("COUNT(*) > 1")
                                  .count

    if duplicate_guilds.any?
      detail = duplicate_guilds.map { |g, n| "guild_id=#{g}: #{n} active runs" }.join("; ")
      raise ActiveRecord::IrreversibleMigration, <<~MSG.squish
        Cannot enforce one-active-run-per-guild: #{detail}.
        Deactivate the extras manually before re-running, e.g.
        SoulLinkRun.where(guild_id: <id>, active: true).order(:run_number).limit(<n - 1>).update_all(active: false)
      MSG
    end

    # MySQL 8 virtual generated column. Value is guild_id when active is
    # true, NULL otherwise. NULLs don't conflict in unique indexes, so
    # multiple inactive runs per guild remain fine. The unique index on
    # this column enforces the invariant at the storage layer — any path
    # (controller, channel, raw SQL, manual tampering) that tries to
    # produce a second active run for a guild fails with a duplicate-key
    # error.
    add_column :soul_link_runs, :active_guild_id, :bigint,
               as: "(CASE WHEN active = 1 THEN guild_id END)"

    add_index :soul_link_runs, :active_guild_id, unique: true,
              name: "index_soul_link_runs_on_active_guild_id"
  end

  def down
    remove_index :soul_link_runs, name: "index_soul_link_runs_on_active_guild_id"
    remove_column :soul_link_runs, :active_guild_id
  end
end
