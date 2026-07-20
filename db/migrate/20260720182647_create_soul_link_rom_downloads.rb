class CreateSoulLinkRomDownloads < ActiveRecord::Migration[8.1]
  def change
    create_table :soul_link_rom_downloads do |t|
      t.references :soul_link_run, null: false, foreign_key: true
      t.bigint  :discord_user_id, null: false
      t.string  :status, null: false, default: "pending"
      t.string  :rom_path
      t.string  :error_message
      t.timestamps
    end

    add_index :soul_link_rom_downloads, [ :soul_link_run_id, :discord_user_id ]
  end
end
