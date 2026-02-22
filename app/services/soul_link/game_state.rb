# app/services/soul_link/game_state.rb
module SoulLink
  class GameState
    GYM_INFO_PATH = Rails.root.join('config', 'soul_link', 'gym_info.yml')
    LOCATIONS_PATH = Rails.root.join('config', 'soul_link', 'locations.yml')
    SETTINGS_PATH = Rails.root.join('config', 'soul_link', 'settings.yml')

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

      def next_gym_info
        run = SoulLinkRun.current
        return first_gym_info unless run

        # Determine which gym is next based on number of gyms defeated
        # For now, simple logic - you can enhance this
        gyms_defeated = 0 # You might track this separately

        gym_key = case gyms_defeated
                  when 0 then :first_gym
                  when 1 then :second_gym
                  # Add more as needed
                  else
                    :first_gym
                  end

        gym_info[gym_key.to_s] || first_gym_info
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

      def reload!
        @gym_info = nil
        @locations = nil
        @settings = nil
      end
    end
  end
end