module SoulLink
  class TypeChart
    # Gen IV type list (17 types — Fairy not yet introduced)
    TYPES = %w[
      Normal Fire Water Electric Grass Ice Fighting Poison
      Ground Flying Psychic Bug Rock Ghost Dragon Dark Steel
    ].freeze

    # Effectiveness multipliers: attacking_type => { defending_type => multiplier }
    # Only non-1.0 values stored. Missing entries default to 1.0 (neutral).
    # 2.0 = super effective, 0.5 = not very effective, 0 = immune
    CHART = {
      "Normal"   => { "Rock" => 0.5, "Ghost" => 0, "Steel" => 0.5 },
      "Fire"     => { "Fire" => 0.5, "Water" => 0.5, "Grass" => 2, "Ice" => 2,
                      "Bug" => 2, "Rock" => 0.5, "Dragon" => 0.5, "Steel" => 2 },
      "Water"    => { "Fire" => 2, "Water" => 0.5, "Grass" => 0.5, "Ground" => 2,
                      "Rock" => 2, "Dragon" => 0.5 },
      "Electric" => { "Water" => 2, "Electric" => 0.5, "Grass" => 0.5, "Ground" => 0,
                      "Flying" => 2, "Dragon" => 0.5 },
      "Grass"    => { "Fire" => 0.5, "Water" => 2, "Grass" => 0.5, "Poison" => 0.5,
                      "Ground" => 2, "Flying" => 0.5, "Bug" => 0.5, "Rock" => 2,
                      "Dragon" => 0.5, "Steel" => 0.5 },
      "Ice"      => { "Fire" => 0.5, "Water" => 0.5, "Grass" => 2, "Ice" => 0.5,
                      "Ground" => 2, "Flying" => 2, "Dragon" => 2, "Steel" => 0.5 },
      "Fighting" => { "Normal" => 2, "Ice" => 2, "Poison" => 0.5, "Flying" => 0.5,
                      "Psychic" => 0.5, "Bug" => 0.5, "Rock" => 2, "Ghost" => 0,
                      "Dark" => 2, "Steel" => 2 },
      "Poison"   => { "Grass" => 2, "Poison" => 0.5, "Ground" => 0.5, "Rock" => 0.5,
                      "Ghost" => 0.5, "Steel" => 0 },
      "Ground"   => { "Fire" => 2, "Electric" => 2, "Grass" => 0.5, "Poison" => 2,
                      "Flying" => 0, "Bug" => 0.5, "Rock" => 2, "Steel" => 2 },
      "Flying"   => { "Electric" => 0.5, "Grass" => 2, "Fighting" => 2, "Bug" => 2,
                      "Rock" => 0.5, "Steel" => 0.5 },
      "Psychic"  => { "Fighting" => 2, "Poison" => 2, "Psychic" => 0.5, "Dark" => 0,
                      "Steel" => 0.5 },
      "Bug"      => { "Fire" => 0.5, "Grass" => 2, "Fighting" => 0.5, "Poison" => 0.5,
                      "Flying" => 0.5, "Psychic" => 2, "Ghost" => 0.5, "Dark" => 2,
                      "Steel" => 0.5 },
      "Rock"     => { "Fire" => 2, "Ice" => 2, "Fighting" => 0.5, "Ground" => 0.5,
                      "Flying" => 2, "Bug" => 2, "Steel" => 0.5 },
      "Ghost"    => { "Normal" => 0, "Psychic" => 2, "Ghost" => 2, "Dark" => 0.5,
                      "Steel" => 0.5 },
      "Dragon"   => { "Dragon" => 2, "Steel" => 0.5 },
      "Dark"     => { "Fighting" => 0.5, "Psychic" => 2, "Ghost" => 2, "Dark" => 0.5,
                      "Steel" => 0.5 },
      "Steel"    => { "Fire" => 0.5, "Water" => 0.5, "Electric" => 0.5, "Ice" => 2,
                      "Rock" => 2, "Steel" => 0.5 }
    }.freeze

    class << self
      # Returns the effectiveness multiplier for an attacking type vs a defending type.
      def effectiveness(attacking_type, defending_type)
        CHART.dig(attacking_type, defending_type) || 1.0
      end

      # Is attacking_type super effective against defending_type?
      def super_effective?(attacking_type, defending_type)
        effectiveness(attacking_type, defending_type) >= 2.0
      end

      # Given an array of defending types (1-2), compute the combined multiplier
      # for a single attacking type. E.g., Electric vs [Water, Flying] = 2×2 = 4×
      def combined_effectiveness(attacking_type, defending_types)
        defending_types.reduce(1.0) { |mult, dt| mult * effectiveness(attacking_type, dt) }
      end

      # Given a defender's type array, return all types that are super effective against it
      # (combined multiplier > 1.0 after accounting for dual typing).
      def weaknesses_for(defending_types)
        TYPES.select { |t| combined_effectiveness(t, defending_types) > 1.0 }
      end

      # Given an attacker's type array, return all defending types it can hit super effectively
      # (at least one STAB type is super effective as a standalone hit).
      def offensive_coverage_for(attacking_types)
        TYPES.select do |defending_type|
          attacking_types.any? { |at| super_effective?(at, defending_type) }
        end
      end

      # Main team analysis method.
      # Takes an array of SoulLinkPokemon records.
      # Returns a hash with all analysis data for the view.
      def analyze_team(pokemon_list)
        return empty_analysis if pokemon_list.empty?

        # Gather each pokemon's types
        team_types = pokemon_list.map { |p| GameState.types_for(p.species) }

        # 1. Offensive coverage: union of all individual coverages
        all_offensive = team_types.flat_map { |types| offensive_coverage_for(types) }.uniq
        offensive_gaps = TYPES - all_offensive

        # 2. Defensive weaknesses: count how many team members are weak to each type
        weakness_counts = Hash.new(0)
        team_types.each do |types|
          next if types.empty?
          weaknesses_for(types).each { |w| weakness_counts[w] += 1 }
        end
        shared_weaknesses = weakness_counts
          .select { |_, count| count >= 2 }
          .sort_by { |_, count| -count }
          .map { |type, count| { type: type, count: count } }

        # 3. Type distribution: count occurrences of each type across team
        type_dist = Hash.new(0)
        team_types.flatten.each { |t| type_dist[t] += 1 }
        type_distribution = type_dist
          .sort_by { |_, count| -count }
          .map { |type, count| { type: type, count: count } }

        # 4. Balance notes (heuristic warnings)
        balance_notes = []

        if offensive_gaps.any?
          balance_notes << {
            level: :warning,
            message: "No super-effective coverage against: #{offensive_gaps.join(', ')}."
          }
        end

        # Over-represented types (3+ team members share a type)
        type_dist.each do |type, count|
          if count >= 3
            balance_notes << {
              level: :warning,
              message: "#{type} is over-represented (#{count} team members). Consider diversifying."
            }
          end
        end

        # Critical shared weaknesses (affecting majority of team)
        majority = (pokemon_list.size / 2.0).ceil
        weakness_counts.each do |type, count|
          if count >= majority
            balance_notes << {
              level: :warning,
              message: "#{count}/#{pokemon_list.size} team members are weak to #{type}. A #{type}-type move could sweep."
            }
          end
        end

        if offensive_gaps.empty? && weakness_counts.none? { |_, c| c >= majority }
          balance_notes << {
            level: :info,
            message: "Good type balance! Full offensive coverage and no critical shared weaknesses."
          }
        end

        {
          offensive_coverage: all_offensive.sort_by { |t| TYPES.index(t) },
          offensive_gaps: offensive_gaps.sort_by { |t| TYPES.index(t) },
          shared_weaknesses: shared_weaknesses,
          type_distribution: type_distribution,
          balance_notes: balance_notes
        }
      end

      private

      def empty_analysis
        {
          offensive_coverage: [],
          offensive_gaps: TYPES.dup,
          shared_weaknesses: [],
          type_distribution: [],
          balance_notes: [{ level: :info, message: "Add Pokémon to your team to see type analysis." }]
        }
      end
    end
  end
end
