class AddDiscordDeathMessageIdToSoulLinkPokemonGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :soul_link_pokemon_groups, :discord_death_message_id, :bigint
  end
end
