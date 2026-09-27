namespace :soul_link do
  desc "Replace 'Species #N' placeholders on auto-detected catches with real species names (DRY_RUN=1 to preview)"
  task backfill_species_names: :environment do
    dry_run = ENV["DRY_RUN"].present?
    names = Pokemon::BaseStat.pluck(:national_dex_number, :species).to_h

    SoulLinkPokemon.where("species LIKE ?", "Species #%").find_each do |pokemon|
      dex_number = pokemon.species[/\ASpecies #(\d+)\z/, 1]&.to_i
      species = names[dex_number]
      if species.nil?
        puts "pokemon=#{pokemon.id}: #{pokemon.species} has no match, skipped"
        next
      end

      attrs = { species: species }
      attrs[:name] = species if pokemon.name == pokemon.species
      puts "pokemon=#{pokemon.id}: #{pokemon.species} -> #{species}"
      pokemon.update!(attrs) unless dry_run
    end
  end
end
