module EmulatorHelper
  # Formats a total seconds count as "Xh Ym" for the run roster sidebar.
  # Returns "—" for nil so the caller can render unconditionally.
  # Examples:
  #   format_play_time(nil)    # => "—"
  #   format_play_time(0)      # => "0h 0m"
  #   format_play_time(3_660)  # => "1h 1m"
  #   format_play_time(45_780) # => "12h 43m"
  def format_play_time(seconds)
    return "—" if seconds.nil?
    s = [ seconds.to_i, 0 ].max
    hours = s / 3600
    minutes = (s % 3600) / 60
    "#{hours}h #{minutes}m"
  end

  # Formats a Pokémon Platinum map header ID as a human-readable name
  # for the run-roster + slot-card surfaces. Returns nil for nil input
  # (callers gate with `if format_map_name(...).present?` or render
  # conditionally on `parsed_map_id.present?`), the canonical name when
  # SoulLink::GameState knows the ID, or a "Map #N" fallback when not —
  # informative enough for v1, and a signal to extend
  # config/soul_link/maps.yml as new IDs are observed in real saves.
  def format_map_name(map_id)
    return nil if map_id.nil?
    SoulLink::GameState.map_name(map_id) || "Map ##{map_id}"
  end

  # Formats a Pokemon Platinum move ID as a human-readable move name
  # for the dashboard PC BOX tab's per-Pokemon STATS pane. Returns nil
  # for nil/zero input (PartyParser pads unused move slots with id=0;
  # the view already filters via `m["id"].to_i.positive?` so this
  # double-guard is defense in depth), the canonical name when
  # SoulLink::GameState knows the ID, or a "Move #N" fallback when not —
  # informative enough for v1 and signals which entries need to be
  # added to config/soul_link/move_names.yml.
  def format_move_name(id)
    return nil if id.nil?
    n = id.to_i
    return nil if n.zero?
    SoulLink::GameState.move_name(n).presence || "Move ##{n}"
  end
end
