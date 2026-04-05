class MakeDiscordChannelIdsOptionalOnSoulLinkRuns < ActiveRecord::Migration[8.1]
  def change
    change_column_null :soul_link_runs, :category_id, true
    change_column_null :soul_link_runs, :general_channel_id, true
    change_column_null :soul_link_runs, :catches_channel_id, true
    change_column_null :soul_link_runs, :deaths_channel_id, true
  end
end
