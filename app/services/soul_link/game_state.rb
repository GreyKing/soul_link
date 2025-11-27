# app/services/soul_link/game_state.rb
module SoulLink
  class GameState
    def self.current_boss_info
      data = YAML.load_file(Rails.root.join("config/soul_link/rally_points.yml"))
      boss = data["current_boss"] || {}

      {
        name: boss["name"] || "Unknown",
        recommended_level: boss["recommended_level"] || "?",
        notes: boss["notes"] || "No notes yet."
      }
    end
  end
end