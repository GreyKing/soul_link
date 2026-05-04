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

  # Formats a "stake" phrase for the inline DELETE confirm body on
  # the save-slot card (Step 21 R3). Communicates how much in-game
  # progress the player is about to lose.
  #
  # Locked rule (architect-approved 2026-05-04):
  #   - nil or seconds < 60        → "less than a minute of progress"
  #   - 60 ≤ seconds < 120         → "1 minute of progress"      (singular)
  #   - 120 ≤ seconds < 3600       → "N minutes of progress"     (N = seconds/60, integer div)
  #   - 3600 ≤ seconds < 7200      → "1 hour of progress"        (singular)
  #   - seconds ≥ 7200             → "N hours of progress"       (N = seconds/3600, integer div)
  #
  # Integer-division (truncating) on the hour figure keeps the phrase
  # honest about "at least N hours" — 3h59m says "3 hours of progress",
  # not "4 hours of progress". No zero-padding.
  def format_progress_phrase(seconds)
    s = seconds.to_i
    return "less than a minute of progress" if seconds.nil? || s < 60
    if s < 3600
      minutes = s / 60
      return "1 minute of progress" if minutes == 1
      "#{minutes} minutes of progress"
    else
      hours = s / 3600
      return "1 hour of progress" if hours == 1
      "#{hours} hours of progress"
    end
  end
end
