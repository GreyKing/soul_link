module SoulLink
  # Pure function that compares two snapshots of a save slot's parsed
  # state and returns the structured diff events the auto-tracking
  # coordinators consume.
  #
  # **Contract: zero side effects.** No `Rails.logger`, no AR, no
  # `Time.current`. Pure integer arithmetic on the inputs. The
  # coordinator (`SoulLink::GymBeatenCoordinator` and any future
  # category-2/3 siblings) owns all observable behavior.
  #
  # Step 15 ships only the badge dimension. Categories 2 (gym battle
  # teams) and 3 (catches + routes) extend the `Result` struct with new
  # keyword fields (`catch_events:`, `evolution_events:`, etc.) without
  # rewriting existing call sites — that's the architectural call from
  # the SRAM auto-tracking audit.
  module SaveDiff
    BadgeGained = Struct.new(:gym_number, keyword_init: true)
    BadgeLost   = Struct.new(:gym_number, keyword_init: true)

    Result = Struct.new(:badge_events, keyword_init: true) do
      def empty?
        badge_events.empty?
      end
    end

    # Compares two `parsed_badges` snapshots and emits one event per
    # bit that changed.
    #
    # @param prev_badges [Integer, nil] previous parsed_badges count.
    #   Nil means "no prior baseline" (first-ever parse) and short-
    #   circuits to an empty Result — the caller decides whether to
    #   skip the dispatch entirely (preferred — see Layer C in the
    #   Step 15 brief) or fall through to a no-op.
    # @param curr_badges [Integer, nil] current parsed_badges count.
    #   Nil means "parse failed" and short-circuits the same way so a
    #   CRC-bad save sandwiched between two good ones doesn't produce
    #   spurious BadgeLost events (the KG-13 prerequisite).
    # @return [Result] always; badge_events is `[]` if either side is
    #   nil or if the values are equal. Multi-bit jumps emit one event
    #   per gym in sequential order so each runs through the all-4
    #   gate in `GymBeatenCoordinator` independently.
    def self.between(prev_badges:, curr_badges:)
      events = []
      if !prev_badges.nil? && !curr_badges.nil? && prev_badges != curr_badges
        if curr_badges > prev_badges
          ((prev_badges + 1)..curr_badges).each { |n| events << BadgeGained.new(gym_number: n) }
        else
          ((curr_badges + 1)..prev_badges).each { |n| events << BadgeLost.new(gym_number: n) }
        end
      end
      Result.new(badge_events: events)
    end
  end
end
