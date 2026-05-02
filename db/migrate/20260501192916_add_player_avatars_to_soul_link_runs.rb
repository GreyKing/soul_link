class AddPlayerAvatarsToSoulLinkRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_runs, :player_avatars, :json
  end
end
