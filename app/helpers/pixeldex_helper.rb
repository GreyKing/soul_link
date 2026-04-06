module PixeldexHelper
  TYPE_ABBREVIATIONS = {
    "Normal"   => "NRM",
    "Fire"     => "FIR",
    "Water"    => "WTR",
    "Electric" => "ELC",
    "Grass"    => "GRS",
    "Ice"      => "ICE",
    "Fighting" => "FGT",
    "Poison"   => "PSN",
    "Ground"   => "GND",
    "Flying"   => "FLY",
    "Psychic"  => "PSY",
    "Bug"      => "BUG",
    "Rock"     => "RCK",
    "Ghost"    => "GHO",
    "Dragon"   => "DRG",
    "Dark"     => "DRK",
    "Steel"    => "STL"
  }.freeze

  ALL_TYPES = TYPE_ABBREVIATIONS.keys.freeze

  # All 25 natures with stat effects (+increase, -decrease). Neutral natures have nil.
  NATURES = {
    "Hardy"   => { up: nil,    down: nil },
    "Lonely"  => { up: "Atk",  down: "Def" },
    "Brave"   => { up: "Atk",  down: "Spd" },
    "Adamant" => { up: "Atk",  down: "SpA" },
    "Naughty" => { up: "Atk",  down: "SpD" },
    "Bold"    => { up: "Def",  down: "Atk" },
    "Docile"  => { up: nil,    down: nil },
    "Relaxed" => { up: "Def",  down: "Spd" },
    "Impish"  => { up: "Def",  down: "SpA" },
    "Lax"     => { up: "Def",  down: "SpD" },
    "Timid"   => { up: "Spd",  down: "Atk" },
    "Hasty"   => { up: "Spd",  down: "Def" },
    "Serious" => { up: nil,    down: nil },
    "Jolly"   => { up: "Spd",  down: "SpA" },
    "Naive"   => { up: "Spd",  down: "SpD" },
    "Modest"  => { up: "SpA",  down: "Atk" },
    "Mild"    => { up: "SpA",  down: "Def" },
    "Quiet"   => { up: "SpA",  down: "Spd" },
    "Bashful" => { up: nil,    down: nil },
    "Rash"    => { up: "SpA",  down: "SpD" },
    "Calm"    => { up: "SpD",  down: "Atk" },
    "Gentle"  => { up: "SpD",  down: "Def" },
    "Sassy"   => { up: "SpD",  down: "Spd" },
    "Careful" => { up: "SpD",  down: "SpA" },
    "Quirky"  => { up: nil,    down: nil }
  }.freeze

  # Returns a display string like "+Atk -Spd" or "Neutral" for a nature
  def pixeldex_nature_label(nature_name)
    info = NATURES[nature_name]
    return "" unless info
    return "Neutral" if info[:up].nil?
    "+#{info[:up]} -#{info[:down]}"
  end

  # Renders a 3-letter type badge in pixeldex style
  def pixeldex_type_badge(type_name)
    abbr = TYPE_ABBREVIATIONS[type_name] || type_name[0..2].upcase
    content_tag(:span, abbr, class: "type-text")
  end

  # Renders type badges for a species using 3-letter codes
  def pixeldex_type_badges(species_name)
    types = SoulLink::GameState.types_for(species_name)
    return "".html_safe if types.empty?
    safe_join(types.map { |t| pixeldex_type_badge(t) }, " ")
  end

  # Strategy dialog text for the map panel
  def pixeldex_gym_strategy(next_gym, type_analysis)
    return "All gym leaders defeated! Prepare for the ELITE FOUR!" unless next_gym

    leader = next_gym["leader"]&.upcase || "???"
    gym_type = next_gym["type"] || "Unknown"
    abbr = TYPE_ABBREVIATIONS[gym_type] || gym_type[0..2].upcase

    coverage = type_analysis[:offensive_coverage] || []
    has_coverage = coverage.include?(gym_type)

    if has_coverage
      "#{leader} uses #{abbr} types. Your team has good coverage. You're prepared, trainer!"
    else
      "#{leader} uses #{abbr} types. Consider adjusting your team for better matchups."
    end
  end

  # Team status dialog text for the party panel
  def pixeldex_team_dialog(type_analysis, team_size)
    return "No team built yet. Visit the Team page!" if team_size == 0

    notes = type_analysis[:balance_notes] || []
    warnings = notes.select { |n| n[:level] == :warning }

    if warnings.any?
      warnings.first[:message]
    elsif type_analysis[:offensive_gaps]&.empty?
      "Team is at full strength! Full type coverage achieved."
    else
      gaps = (type_analysis[:offensive_gaps] || []).map { |t| TYPE_ABBREVIATIONS[t] || t }
      if gaps.any?
        "Team is solid. Watch out for #{gaps.first(2).join(' and ')} types."
      else
        "Team is at full strength!"
      end
    end
  end

  # Type coverage display data: { covered: ["FIR", ...], gaps: ["ICE", ...] }
  def pixeldex_type_coverage(type_analysis)
    covered = (type_analysis[:offensive_coverage] || []).filter_map { |t| TYPE_ABBREVIATIONS[t] }
    gaps = (type_analysis[:offensive_gaps] || []).filter_map { |t| TYPE_ABBREVIATIONS[t] }
    { covered: covered, gaps: gaps }
  end

  # JSON data for all pokemon in a group (for the modal's linked pokemon section)
  def pixeldex_group_pokemon_json(group, current_user_id)
    SoulLink::GameState.players.map do |player|
      uid = player["discord_user_id"]
      pokemon = group.soul_link_pokemon.find { |p| p.discord_user_id == uid }
      {
        id: pokemon&.id,
        player_name: player["display_name"],
        species: pokemon&.species,
        sprite_url: pokemon&.species.present? ? (ActionController::Base.helpers.asset_path("sprites/#{SoulLink::GameState.sprite_filename(pokemon.species)}.png") rescue nil) : nil,
        level: pokemon&.level,
        ability: pokemon&.ability,
        nature: pokemon&.nature,
        is_mine: uid == current_user_id
      }
    end.to_json
  end

  # Renders a "?" silhouette placeholder for unassigned pokemon
  def pixeldex_unknown_sprite(size: 20)
    content_tag(:span, "?",
      style: "display: inline-flex; align-items: center; justify-content: center; " \
             "width: #{size}px; height: #{size}px; " \
             "background: var(--d2); color: var(--l1); " \
             "font-size: #{size / 2}px; border: 1px solid var(--d1); " \
             "image-rendering: pixelated;")
  end

  # Renders the player-sprite rows for a box cell
  def pixeldex_player_sprites(group, current_user_id, sprite_size: 20)
    SoulLink::GameState.players.map do |player|
      uid = player["discord_user_id"]
      pokemon = group.soul_link_pokemon.find { |p| p.discord_user_id == uid }
      short_name = player["display_name"].to_s[0..3].upcase

      sprite = if pokemon&.species.present?
                 pokemon_sprite_tag(pokemon.species, size: sprite_size)
               else
                 pixeldex_unknown_sprite(size: sprite_size)
               end

      content_tag(:div, safe_join([
        content_tag(:span, short_name, style: "font-size: 7px; color: var(--d2); width: 30px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;"),
        sprite
      ]), style: "display: flex; align-items: center; gap: 2px;")
    end.then { |rows| safe_join(rows) }
  end

  # Returns a hash of species → digested asset URL for sprites (for JS use)
  def pixeldex_sprite_urls
    SoulLink::GameState.pokedex.each_with_object({}) do |(species, file_id), map|
      path = "sprites/#{file_id}.png"
      map[species] = ActionController::Base.helpers.asset_path(path)
    rescue Propshaft::MissingAssetError
      # Skip missing sprites
    end
  end

  # Survival percentage formatted for display
  def pixeldex_survival_pct(caught_count, dead_count)
    return "0%" if caught_count == 0
    pct = ((caught_count - dead_count).to_f / caught_count * 100)
    "#{pct == pct.to_i ? pct.to_i : pct.round(1)}%"
  end

  # Coverage fraction like "15/17"
  def pixeldex_coverage_fraction(type_analysis)
    covered = (type_analysis[:offensive_coverage] || []).size
    "#{covered}/#{ALL_TYPES.size}"
  end

  # Sinnoh ASCII map with current location highlighted
  def pixeldex_ascii_map(current_location_name)
    locations = {
      "Snowpoint"  => "Snowpoint",
      "Eterna"     => "Eterna",
      "Celestic"   => "Celestic",
      "Veilstone"  => "Veilstone",
      "Floaroma"   => "Floaroma",
      "Pastoria"   => "Pastoria",
      "Jubilife"   => "Jubilife",
      "Oreburgh"   => "Oreburgh",
      "Hearthome"  => "Hearthome",
      "Canalave"   => "Canalave",
      "Solaceon"   => "Solaceon"
    }

    # Build the map lines
    map_lines = [
      "SINNOH REGION",
      "\u2550" * 23,
      "                 Snowpoint",
      "                    |",
      "  Eterna---Celestic-+-Veilstone",
      "    |         |         |",
      "  Floaroma  Mt.Coronet  Pastoria",
      "    |         |         |",
      "  Jubilife-Oreburgh  Hearthome",
      "    |                   |",
      "  Canalave          Solaceon",
      "\u2550" * 23
    ]

    # Find and highlight the current location in the map
    loc_name = current_location_name.to_s
    city = locations.keys.find { |k| loc_name.include?(k) }

    result = map_lines.map do |line|
      if city && line.include?(city)
        # Highlight the city name and add marker
        line.gsub(city, "<span class=\"map-you\">#{city}</span>")
      else
        ERB::Util.html_escape(line)
      end
    end

    # Add YOU marker below the highlighted city
    if city
      result << "<span class=\"map-you\">  \u25B2 YOU</span>"
    end

    result.join("\n").html_safe
  end
end
