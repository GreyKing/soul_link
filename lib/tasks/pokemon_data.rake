require "net/http"
require "json"
require "yaml"
require "fileutils"

module PokemonDataFetcher
  POKEAPI_BASE = "https://pokeapi.co/api/v2"

  POKEAPI_NAME_MAP = {
    "nidoran-f" => "Nidoran\u2640",
    "nidoran-m" => "Nidoran\u2642",
    "farfetchd" => "Farfetch'd",
    "mr-mime"   => "Mr. Mime",
    "mime-jr"   => "Mime Jr.",
    "porygon-z" => "Porygon-Z",
    "ho-oh"     => "Ho-Oh"
  }.freeze

  STAT_NAME_MAP = {
    "hp"              => :hp,
    "attack"          => :atk,
    "defense"         => :def_stat,
    "special-attack"  => :spa,
    "special-defense" => :spd,
    "speed"           => :spe
  }.freeze

  def self.normalize_species_name(api_name)
    POKEAPI_NAME_MAP[api_name] || api_name.split("-").map(&:capitalize).join(" ")
  end

  def self.normalize_move_name(api_name)
    api_name.split("-").map(&:capitalize).join(" ")
  end

  def self.fetch_json(path)
    uri = URI("#{POKEAPI_BASE}#{path}")
    response = Net::HTTP.get_response(uri)
    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP #{response.code} for #{path}"
    end
    JSON.parse(response.body)
  end

  def self.normalize_ability_name(api_name)
    api_name.split("-").map(&:capitalize).join(" ")
  end

  def self.extract_species_fields(species_data)
    # genus (English)
    genus_entry = species_data["genera"]&.find { |g| g["language"]["name"] == "en" }
    genus = genus_entry ? genus_entry["genus"] : nil

    # flavor_text: prefer Platinum, fall back to Diamond, English only
    flavor_entry = species_data["flavor_text_entries"]&.find do |fte|
      fte["language"]["name"] == "en" && fte["version"]["name"] == "platinum"
    end
    flavor_entry ||= species_data["flavor_text_entries"]&.find do |fte|
      fte["language"]["name"] == "en" && fte["version"]["name"] == "diamond"
    end
    flavor_text = flavor_entry ? flavor_entry["flavor_text"].gsub(/[\n\f\r]/, " ").squeeze(" ").strip : nil

    # egg_groups
    egg_groups = (species_data["egg_groups"] || []).map { |eg| eg["name"] }

    # growth_rate
    growth_rate = species_data.dig("growth_rate", "name")

    {
      "base_happiness" => species_data["base_happiness"],
      "capture_rate" => species_data["capture_rate"],
      "gender_rate" => species_data["gender_rate"],
      "growth_rate" => growth_rate,
      "egg_groups" => egg_groups,
      "genus" => genus,
      "flavor_text" => flavor_text,
      "is_legendary" => species_data["is_legendary"],
      "is_mythical" => species_data["is_mythical"],
      "hatch_counter" => species_data["hatch_counter"]
    }
  end

  def self.extract_move_effect(data)
    effect_entry = data["effect_entries"]&.find { |e| e["language"]["name"] == "en" }
    return nil unless effect_entry

    short_effect = effect_entry["short_effect"]
    effect_chance = data["effect_chance"]
    short_effect = short_effect.gsub("$effect_chance", effect_chance.to_s) if effect_chance && short_effect
    short_effect
  end

  def self.extract_move_meta(data)
    meta = data["meta"]
    return nil unless meta

    {
      "ailment" => meta.dig("ailment", "name"),
      "ailment_chance" => meta["ailment_chance"],
      "drain" => meta["drain"],
      "healing" => meta["healing"],
      "crit_rate" => meta["crit_rate"],
      "flinch_chance" => meta["flinch_chance"],
      "min_hits" => meta["min_hits"],
      "max_hits" => meta["max_hits"]
    }
  end

  def self.extract_move_flavor_text(data)
    # Prefer platinum version group, fall back to diamond-pearl
    entry = data["flavor_text_entries"]&.find do |fte|
      fte["language"]["name"] == "en" && fte["version_group"]["name"] == "platinum"
    end
    entry ||= data["flavor_text_entries"]&.find do |fte|
      fte["language"]["name"] == "en" && fte["version_group"]["name"] == "diamond-pearl"
    end
    entry ? entry["flavor_text"].gsub(/[\n\f\r]/, " ").squeeze(" ").strip : nil
  end
end

namespace :pokemon do

  desc "Fetch Gen IV Platinum data from PokeAPI into local YAML cache"
  task fetch: :environment do
    output_dir = Rails.root.join("config", "pokemon_data")
    FileUtils.mkdir_p(output_dir)

    base_stats = {}
    learnsets = {}
    move_names_needed = Set.new
    failures = 0

    # Phase 1: Fetch pokemon (dex #1-493) — 2 requests each (/pokemon/{id} + /pokemon-species/{id})
    puts "Phase 1: Fetching pokemon data (2 requests each)..."
    (1..493).each do |id|
      begin
        data = PokemonDataFetcher.fetch_json("/pokemon/#{id}")
        species_data = PokemonDataFetcher.fetch_json("/pokemon-species/#{id}")
        api_name = data["name"]
        species = PokemonDataFetcher.normalize_species_name(api_name)

        # Extract stats
        stats = {}
        data["stats"].each do |stat_entry|
          key = PokemonDataFetcher::STAT_NAME_MAP[stat_entry["stat"]["name"]]
          stats[key] = stat_entry["base_stat"] if key
        end

        # Extract types
        types = data["types"].sort_by { |t| t["slot"] }
        type1 = types[0]["type"]["name"].capitalize
        type2 = types[1] ? types[1]["type"]["name"].capitalize : nil

        # Extract abilities
        abilities = data["abilities"].sort_by { |a| a["slot"] }.map do |a|
          {
            "name" => PokemonDataFetcher.normalize_ability_name(a["ability"]["name"]),
            "is_hidden" => a["is_hidden"]
          }
        end

        # Extract species-level fields
        species_fields = PokemonDataFetcher.extract_species_fields(species_data)

        base_stats[species] = {
          "national_dex_number" => id,
          "hp" => stats[:hp],
          "atk" => stats[:atk],
          "def_stat" => stats[:def_stat],
          "spa" => stats[:spa],
          "spd" => stats[:spd],
          "spe" => stats[:spe],
          "type1" => type1,
          "type2" => type2,
          "base_experience" => data["base_experience"],
          "height" => data["height"],
          "weight" => data["weight"],
          "abilities" => abilities
        }.merge(species_fields)

        # Extract Platinum learnset
        pokemon_learnset = []
        data["moves"].each do |move_entry|
          platinum_details = move_entry["version_group_details"].select do |vgd|
            vgd["version_group"]["name"] == "platinum"
          end

          next if platinum_details.empty?

          move_api_name = move_entry["move"]["name"]
          move_display_name = PokemonDataFetcher.normalize_move_name(move_api_name)
          move_names_needed << move_api_name

          platinum_details.each do |detail|
            pokemon_learnset << {
              "move" => move_display_name,
              "learn_method" => detail["move_learn_method"]["name"],
              "level_learned" => detail["level_learned_at"] == 0 ? nil : detail["level_learned_at"]
            }
          end
        end

        learnsets[species] = pokemon_learnset unless pokemon_learnset.empty?
      rescue => e
        failures += 1
        puts "  ERROR fetching pokemon #{id}: #{e.message}"
      end

      if id % 50 == 0
        puts "  Fetched #{id}/493 pokemon (2 requests each)..."
      end
    end
    puts "  Fetched 493/493 pokemon (#{failures} failures)."

    # Phase 2: Fetch moves
    puts "\nPhase 2: Fetching move data..."
    moves_data = {}
    move_list = move_names_needed.to_a.sort
    total_moves = move_list.size

    move_list.each_with_index do |move_api_name, idx|
      begin
        data = PokemonDataFetcher.fetch_json("/move/#{move_api_name}")

        # Skip moves from Gen V+ (they didn't exist in Gen IV)
        generation_url = data["generation"]["url"]
        gen_number = generation_url.match(%r{/generation/(\d+)/})[1].to_i
        if gen_number > 4
          next
        end

        display_name = PokemonDataFetcher.normalize_move_name(move_api_name)
        moves_data[display_name] = {
          "power" => data["power"],
          "move_type" => data["type"]["name"].capitalize,
          "category" => data["damage_class"]["name"],
          "accuracy" => data["accuracy"],
          "pp" => data["pp"],
          "priority" => data["priority"],
          "effect" => PokemonDataFetcher.extract_move_effect(data),
          "flavor_text" => PokemonDataFetcher.extract_move_flavor_text(data),
          "meta" => PokemonDataFetcher.extract_move_meta(data)
        }
      rescue => e
        failures += 1
        puts "  ERROR fetching move '#{move_api_name}': #{e.message}"
      end

      count = idx + 1
      if count % 50 == 0
        puts "  Fetched #{count}/#{total_moves} moves..."
      end
    end
    skipped_moves = total_moves - moves_data.size
    puts "  Processed #{total_moves}/#{total_moves} moves (#{moves_data.size} kept, #{skipped_moves} skipped Gen V+)."

    # Write YAML files
    puts "\nWriting YAML files..."
    File.write(output_dir.join("base_stats.yml"), base_stats.to_yaml)
    puts "  Wrote base_stats.yml (#{base_stats.size} pokemon)"

    File.write(output_dir.join("moves.yml"), moves_data.to_yaml)
    puts "  Wrote moves.yml (#{moves_data.size} moves)"

    File.write(output_dir.join("learnsets.yml"), learnsets.to_yaml)
    puts "  Wrote learnsets.yml (#{learnsets.size} pokemon with learnsets)"

    puts "\nDone!"
    puts "  Failures: #{failures}" if failures > 0
  end

  desc "Seed database from local YAML cache files"
  task seed: :environment do
    data_dir = Rails.root.join("config", "pokemon_data")

    %w[base_stats.yml moves.yml learnsets.yml].each do |file|
      unless File.exist?(data_dir.join(file))
        puts "Missing #{file} — run `rake pokemon:fetch` first."
        exit 1
      end
    end

    base_stats_data = YAML.safe_load_file(data_dir.join("base_stats.yml"))
    moves_data      = YAML.safe_load_file(data_dir.join("moves.yml"))
    learnsets_data  = YAML.safe_load_file(data_dir.join("learnsets.yml"))

    # Phase 1: Upsert base stats
    puts "Phase 1: Seeding pokemon_base_stats..."
    stats_created = 0
    stats_existing = 0
    ActiveRecord::Base.transaction do
      base_stats_data.each do |species, attrs|
        record = Pokemon::BaseStat.find_or_initialize_by(species: species)
        is_new = record.new_record?
        record.assign_attributes(attrs.slice(
          "national_dex_number", "hp", "atk", "def_stat", "spa", "spd", "spe",
          "type1", "type2",
          "base_experience", "height", "weight", "abilities",
          "base_happiness", "capture_rate", "gender_rate", "growth_rate",
          "egg_groups", "genus", "flavor_text",
          "is_legendary", "is_mythical", "hatch_counter"
        ))
        record.save!
        is_new ? stats_created += 1 : stats_existing += 1
      end
    end
    puts "  #{stats_created} pokemon base stats created, #{stats_existing} already existed."

    # Phase 2: Upsert moves
    puts "Phase 2: Seeding pokemon_moves..."
    moves_created = 0
    moves_existing = 0
    ActiveRecord::Base.transaction do
      moves_data.each do |name, attrs|
        record = Pokemon::Move.find_or_initialize_by(name: name)
        is_new = record.new_record?
        move_attrs = attrs.slice(
          "power", "move_type", "category", "accuracy", "pp", "priority",
          "effect", "flavor_text"
        )
        if attrs["meta"].is_a?(Hash)
          move_attrs.merge!(attrs["meta"].slice(
            "crit_rate", "drain", "healing", "flinch_chance",
            "min_hits", "max_hits", "ailment", "ailment_chance"
          ))
        end
        record.assign_attributes(move_attrs)
        record.save!
        is_new ? moves_created += 1 : moves_existing += 1
      end
    end
    puts "  #{moves_created} moves created, #{moves_existing} already existed."

    # Phase 3: Create learnsets
    puts "Phase 3: Seeding pokemon_learnsets..."
    learnset_created = 0
    learnset_existing = 0
    skipped = 0
    ActiveRecord::Base.transaction do
      learnsets_data.each do |species, entries|
        base_stat = Pokemon::BaseStat.find_by(species: species)
        unless base_stat
          skipped += 1
          next
        end

        entries.each do |entry|
          move = Pokemon::Move.find_by(name: entry["move"])
          unless move
            skipped += 1
            next
          end

          record = Pokemon::Learnset.find_or_initialize_by(
            pokemon_base_stat_id: base_stat.id,
            pokemon_move_id: move.id,
            learn_method: entry["learn_method"]
          )
          if record.new_record?
            record.level_learned = entry["level_learned"]
            record.save!
            learnset_created += 1
          else
            learnset_existing += 1
          end
        end
      end
    end
    puts "  #{learnset_created} learnset entries created, #{learnset_existing} already existed (#{skipped} skipped)."

    # Summary: check for pokedex.yml mismatches
    puts "\n--- Summary ---"
    puts "  pokemon_base_stats: #{Pokemon::BaseStat.count}"
    puts "  pokemon_moves:      #{Pokemon::Move.count}"
    puts "  pokemon_learnsets:   #{Pokemon::Learnset.count}"

    pokedex_path = Rails.root.join("config", "soul_link", "pokedex.yml")
    if File.exist?(pokedex_path)
      pokedex = YAML.safe_load_file(pokedex_path)
      pokedex_names = pokedex.keys.to_set
      seeded_names = Pokemon::BaseStat.pluck(:species).to_set

      missing_from_pokedex = seeded_names - pokedex_names
      if missing_from_pokedex.any?
        puts "\n  Names in base_stats but NOT in pokedex.yml (#{missing_from_pokedex.size}):"
        missing_from_pokedex.sort.first(20).each { |name| puts "    - #{name}" }
        puts "    ... and #{missing_from_pokedex.size - 20} more" if missing_from_pokedex.size > 20
      else
        puts "\n  All seeded species match pokedex.yml keys."
      end
    else
      puts "\n  pokedex.yml not found — skipping name mismatch check."
    end
  end
end
