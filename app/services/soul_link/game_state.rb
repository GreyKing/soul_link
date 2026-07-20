# app/services/soul_link/game_state.rb
module SoulLink
  class GameState
    GYM_INFO_PATH = Rails.root.join('config', 'soul_link', 'gym_info.yml')
    LOCATIONS_PATH = Rails.root.join('config', 'soul_link', 'locations.yml')
    SETTINGS_PATH = Rails.root.join('config', 'soul_link', 'settings.yml')
    POKEDEX_PATH = Rails.root.join('config', 'soul_link', 'pokedex.yml')
    MAPS_PATH = Rails.root.join('config', 'soul_link', 'maps.yml')
    MET_LOCATIONS_PATH = Rails.root.join('config', 'soul_link', 'met_locations.yml')
    MOVE_NAMES_PATH = Rails.root.join('config', 'soul_link', 'move_names.yml')
    MAP_COORDINATES_PATH = Rails.root.join('config', 'soul_link', 'map_coordinates.yml')
    PROGRESSION_PATH = Rails.root.join('config', 'soul_link', 'progression.yml')
    TYPES_PATH = Rails.root.join('config', 'soul_link', 'types.yml')
    ABILITIES_PATH = Rails.root.join('config', 'soul_link', 'abilities.yml')
    EVOLUTIONS_PATH = Rails.root.join('config', 'soul_link', 'evolutions.yml')
    CHEATS_PATH = Rails.root.join('config', 'soul_link', 'cheats.yml')

    class << self
      def gym_info
        @gym_info ||= YAML.load_file(GYM_INFO_PATH)
      end

      def locations
        @locations ||= YAML.load_file(LOCATIONS_PATH)
      end

      def settings
        @settings ||= File.exist?(SETTINGS_PATH) ? YAML.load_file(SETTINGS_PATH) : {}
      end

      def category_name(run_number)
        prefix = settings['category_prefix'] || 'Platinum Run'
        "#{prefix} #{run_number}"
      end

      def map_coordinates
        @map_coordinates ||= File.exist?(MAP_COORDINATES_PATH) ? YAML.load_file(MAP_COORDINATES_PATH) : {}
      end

      def progression
        @progression ||= File.exist?(PROGRESSION_PATH) ? YAML.load_file(PROGRESSION_PATH) : {}
      end

      GYM_KEYS = %w[first_gym second_gym third_gym fourth_gym fifth_gym sixth_gym seventh_gym eighth_gym].freeze

      def next_gym_info(gyms_defeated = 0)
        return nil if gyms_defeated >= 8
        key = GYM_KEYS[gyms_defeated]
        gym_info[key]
      end

      def gym_info_by_number(n)
        return nil unless n.between?(1, 8)
        gym_info[GYM_KEYS[n - 1]]
      end

      def first_gym_info
        gym_info['first_gym'] || {}
      end

      def location_choices
        locations.map do |key, data|
          {
            label: data['name'],
            value: key.to_s
          }
        end
      end

      def location_name(key)
        locations.dig(key.to_s, 'name') || key.to_s.titleize
      end

      # Pokémon Platinum SRAM-parsed map header IDs (integer) →
      # `{ name: "..." }` hashes. Loaded from config/soul_link/maps.yml;
      # see that file's header for the source + validation status.
      # Returns {} if the file is missing.
      def maps
        @maps ||= File.exist?(MAPS_PATH) ? (YAML.load_file(MAPS_PATH) || {}) : {}
      end

      # Returns the human-readable name for a map ID, or nil if the ID
      # is unknown or nil. Callers typically use EmulatorHelper#
      # format_map_name to get a "Map #N" fallback for unknown IDs.
      # Accepts integer or numeric-string input (coerced via to_i).
      def map_name(map_id)
        return nil if map_id.nil?
        maps.dig(map_id.to_i, "name")
      end

      # Pokemon Platinum **met-location** IDs (per-PKM Block-B
      # `MetLocation_PtHGSS` u16 at decrypted record offset
      # `0x46-0x47`) → `{ name: "Route 201" [, event: true] }` hashes.
      # **Different enum from `maps`** — see config/soul_link/met_locations.yml
      # header for the source citation (closes KG-12).
      def met_locations
        @met_locations ||= File.exist?(MET_LOCATIONS_PATH) ? (YAML.load_file(MET_LOCATIONS_PATH) || {}) : {}
      end

      # Returns the human-readable name for a met-location ID, or nil if
      # the ID is unknown or nil. Callers should fall back to a
      # "Met-Location ##{id}" string the same way EmulatorHelper#
      # format_map_name handles unknown map IDs.
      def met_location_name(id)
        return nil if id.nil?
        met_locations.dig(id.to_i, "name")
      end

      # Pokemon Platinum move IDs (1..467) → English move names. Loaded
      # from config/soul_link/move_names.yml; see that file's header for
      # the source citation (closes KG-24). Returns {} when the file is
      # absent. Move ID 0 ("no move" sentinel) is intentionally omitted —
      # the PC-box view filters via `m["id"].to_i.positive?`.
      def move_names
        @move_names ||= File.exist?(MOVE_NAMES_PATH) ? (YAML.load_file(MOVE_NAMES_PATH) || {}) : {}
      end

      # Returns the canonical English name for a move ID, or nil if the
      # ID is unknown or nil. Callers (EmulatorHelper#format_move_name)
      # fall back to "Move #N" for unknown IDs the same way
      # `format_map_name` handles unknown map IDs.
      def move_name(id)
        return nil if id.nil?
        move_names[id.to_i]
      end

      # True for met-location IDs flagged `event: true` in
      # met_locations.yml (daycare, link trade, mystery gift,
      # ranger, faraway-place sentinels). Used by `CatchCoordinator`
      # to tag rows with `acquired_via: 'event_gift'` instead of
      # `'catch'`. Returns false for nil and for unknown IDs (a
      # missing ID is treated as a real-world location until proven
      # otherwise — false-positives on event flag are worse than
      # false-negatives).
      def event_met_location?(id)
        return false if id.nil?
        entry = met_locations[id.to_i]
        entry.is_a?(Hash) && entry["event"] == true
      end

      # Player management for multi-player species tracking
      def players
        settings['players'] || []
      end

      def player_ids
        players.map { |p| p['discord_user_id'] }
      end

      def player_name(discord_user_id)
        player = players.find { |p| p['discord_user_id'] == discord_user_id }
        player&.fetch('display_name', nil) || "Player #{discord_user_id}"
      end

      def registered_player?(discord_user_id)
        player_ids.include?(discord_user_id)
      end

      # Pokedex: species name → sprite filename mapping
      def pokedex
        @pokedex ||= File.exist?(POKEDEX_PATH) ? YAML.load_file(POKEDEX_PATH) : {}
      end

      # Returns the sprite filename (without extension) for a species, or nil
      def sprite_filename(species_name)
        pokedex[species_name]
      end

      # Pokemon types: species name → array of 1-2 types
      def pokemon_types
        @pokemon_types ||= File.exist?(TYPES_PATH) ? YAML.load_file(TYPES_PATH) : {}
      end

      # Returns type array for a species, e.g. ["Grass", "Poison"], or []
      def types_for(species_name)
        pokemon_types[species_name] || []
      end

      # Abilities: species name → array of ability strings
      def pokemon_abilities
        @pokemon_abilities ||= File.exist?(ABILITIES_PATH) ? YAML.load_file(ABILITIES_PATH) : {}
      end

      # Returns abilities array for a species, e.g. ["Overgrow"], or []
      def abilities_for(species_name)
        pokemon_abilities[species_name] || []
      end

      # Every ability in the game, sorted and deduplicated (123 of them).
      # Any Pokemon may now have any ability, so the detail-page selector
      # offers the whole list rather than a species-restricted subset.
      def all_abilities
        @all_abilities ||= pokemon_abilities.values.flatten.uniq.sort
      end

      # Evolutions: species name → hash with evolves_to, level/method
      def evolutions
        @evolutions ||= File.exist?(EVOLUTIONS_PATH) ? YAML.load_file(EVOLUTIONS_PATH) : {}
      end

      # Returns evolution info hash for a species, or nil if no evolution
      def evolution_info(species_name)
        data = evolutions[species_name]
        return nil if data.nil? || data.empty?
        data
      end

      # Action Replay cheats. Returns the parsed YAML hash (e.g.
      # { "action_replay" => [...] }) or {} if the file is absent.
      def cheats
        @cheats ||= File.exist?(CHEATS_PATH) ? (YAML.load_file(CHEATS_PATH) || {}) : {}
      end

      def reload!
        @gym_info = nil
        @locations = nil
        @settings = nil
        @pokedex = nil
        @maps = nil
        @met_locations = nil
        @move_names = nil
        @map_coordinates = nil
        @progression = nil
        @pokemon_types = nil
        @pokemon_abilities = nil
        @all_abilities = nil
        @evolutions = nil
        @cheats = nil
      end
    end
  end
end