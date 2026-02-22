module MapHelper
  # Pin radius based on location type — cities get bigger pins
  def pin_radius(loc_type)
    case loc_type
    when "city" then 9
    when "town" then 8
    when "lake" then 7
    when "dungeon" then 6
    else 6  # route
    end
  end

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
end
