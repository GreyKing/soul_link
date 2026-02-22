module MapHelper
  # Returns SVG fill color based on location catch status
  def location_fill(status, type: "route")
    case status
    when "caught"
      type == "lake" ? "#1e40af" : "#1e3a5f"
    when "dead"
      "#7f1d1d"
    else
      type == "lake" ? "#1e293b" : "#374151"
    end
  end

  # Returns SVG stroke color based on location catch status
  def location_stroke(status, type: "route")
    case status
    when "caught"
      "#3b82f6"
    when "dead"
      "#ef4444"
    else
      type == "lake" ? "#1e3a5f" : "#4b5563"
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
