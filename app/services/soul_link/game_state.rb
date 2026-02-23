# app/services/soul_link/game_state.rb
module SoulLink
  class GameState
    GYM_INFO_PATH = Rails.root.join('config', 'soul_link', 'gym_info.yml')
    LOCATIONS_PATH = Rails.root.join('config', 'soul_link', 'locations.yml')
    SETTINGS_PATH = Rails.root.join('config', 'soul_link', 'settings.yml')
    POKEDEX_PATH = Rails.root.join('config', 'soul_link', 'pokedex.yml')
    MAP_COORDINATES_PATH = Rails.root.join('config', 'soul_link', 'map_coordinates.yml')
    PROGRESSION_PATH = Rails.root.join('config', 'soul_link', 'progression.yml')

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

      def reload!
        @gym_info = nil
        @locations = nil
        @settings = nil
        @pokedex = nil
        @map_coordinates = nil
        @progression = nil
      end
    end
  end
end