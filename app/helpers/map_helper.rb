module MapHelper
  # Returns the "best" status for a location that may have multiple groups
  # Priority: caught > dead > uncaught
  def location_status(groups)
    return "uncaught" if groups.blank?
    return "caught" if groups.any?(&:caught?)
    return "dead" if groups.any?(&:dead?)
    "uncaught"
  end

  # Returns the primary (most recent caught) group for a location
  def primary_group(groups)
    return nil if groups.blank?
    groups.find(&:caught?) || groups.first
  end

  # Build JSON data for a location's groups (used in data-groups attributes)
  def groups_json_for(groups)
    return "[]" if groups.blank?
    groups.map do |g|
      {
        nickname: g.nickname,
        status: g.status,
        caught_at: g.caught_at&.strftime("%b %d"),
        eulogy: g.eulogy,
        pokemon: g.soul_link_pokemon.map { |p|
          {
            species: p.species,
            player: SoulLink::GameState.player_name(p.discord_user_id),
            sprite: SoulLink::GameState.sprite_filename(p.species)
          }
        }
      }
    end.to_json
  end

  # Tailwind classes for timeline node sizing by location type
  def timeline_node_size(loc_type)
    case loc_type
    when "city" then "w-9 h-9"
    when "town" then "w-8 h-8"
    when "lake" then "w-7 h-7"
    when "dungeon" then "w-7 h-7"
    when "special" then "w-8 h-8"
    else "w-6 h-6" # route
    end
  end
end
