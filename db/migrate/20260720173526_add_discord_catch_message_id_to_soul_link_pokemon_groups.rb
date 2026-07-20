class AddDiscordCatchMessageIdToSoulLinkPokemonGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_pokemon_groups, :discord_catch_message_id, :bigint
  end
end
