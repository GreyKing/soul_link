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
end
