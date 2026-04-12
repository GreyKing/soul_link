module Pokemon
  class DamageCalculator
    DEFAULT_IVS = { hp: 31, atk: 31, def_stat: 31, spa: 31, spd: 31, spe: 31 }.freeze
    DEFAULT_EVS = { hp: 0, atk: 0, def_stat: 0, spa: 0, spd: 0, spe: 0 }.freeze

    # Gen IV crit stage → chance mapping
    CRIT_CHANCES = { 0 => "6.25%", 1 => "12.5%", 2 => "25%" }.freeze

    # Maps PixeldexHelper NATURES abbreviations to our DB column symbols
    NATURE_STAT_MAP = {
      "Atk" => :atk,
      "Def" => :def_stat,
      "SpA" => :spa,
      "SpD" => :spd,
      "Spd" => :spe
    }.freeze

    class << self
      # Pure stat calculation (non-HP). Exposed publicly for UI stat displays.
      # Returns: Integer
      def calculate_stat(base:, iv: 31, ev: 0, level: 50, nature_modifier: 1.0)
        inner = ((2 * base + iv + (ev / 4)) * level / 100) + 5
        (inner * nature_modifier).floor
      end

      # Main damage calculation.
      #
      # attacker: { species: String, level: Integer, ivs: Hash, evs: Hash, nature: String }
      # defender: { species: String, level: Integer, ivs: Hash, evs: Hash, nature: String }
      # move:     Pokemon::Move record OR { name: String } to look up
      #
      # Returns: { min: Integer, max: Integer, stab: Boolean, effectiveness: Float,
      #            attacker_stat: Integer, defender_stat: Integer }
      def calculate(attacker:, defender:, move:)
        attacker_base = Pokemon::BaseStat.find_by!(species: attacker[:species])
        defender_base = Pokemon::BaseStat.find_by!(species: defender[:species])
        move_record = resolve_move(move)

        # Status moves produce no damage
        if move_record.category == "status" || move_record.power.nil? || move_record.power == 0
          return zero_result
        end

        level = attacker[:level] || 50
        atk_key, def_key = stat_keys_for(move_record.category)

        attacker_ivs = DEFAULT_IVS.merge(attacker[:ivs] || {})
        attacker_evs = DEFAULT_EVS.merge(attacker[:evs] || {})
        defender_ivs = DEFAULT_IVS.merge(defender[:ivs] || {})
        defender_evs = DEFAULT_EVS.merge(defender[:evs] || {})

        atk_stat = compute_stat(attacker_base, atk_key, attacker_ivs[atk_key], attacker_evs[atk_key], level, attacker[:nature])
        def_stat = compute_stat(defender_base, def_key, defender_ivs[def_key], defender_evs[def_key], defender[:level] || 50, defender[:nature])

        # Explosion / Self-Destruct halve defense
        if explosion_move?(move_record)
          def_stat = [def_stat / 2, 1].max
        end

        # Type effectiveness
        effectiveness = SoulLink::TypeChart.combined_effectiveness(move_record.move_type, defender_base.types)

        # Immunity short-circuit
        if effectiveness == 0
          return zero_result(
            stab: stab?(move_record.move_type, attacker_base.types),
            effectiveness: 0.0,
            attacker_stat: atk_stat,
            defender_stat: def_stat
          )
        end

        stab = stab?(move_record.move_type, attacker_base.types)

        # Base damage (before modifiers)
        base_damage = ((((2 * level / 5) + 2) * move_record.power * atk_stat / def_stat) / 50) + 2

        min_damage = apply_modifiers(base_damage, stab, effectiveness, 85)
        max_damage = apply_modifiers(base_damage, stab, effectiveness, 100)

        # Multi-hit support
        hit_min = move_record.respond_to?(:min_hits) ? (move_record.min_hits || 1) : 1
        hit_max = move_record.respond_to?(:max_hits) ? (move_record.max_hits || 1) : 1
        is_multi_hit = hit_min > 1 || hit_max > 1
        min_total = min_damage * hit_min
        max_total = max_damage * hit_max
        avg_hits = (hit_min + hit_max) / 2.0
        avg_total = ((min_damage + max_damage) / 2.0 * avg_hits).round

        # Critical hit support (Gen IV: 2x multiplier)
        crit_stage = move_record.respond_to?(:crit_rate) ? (move_record.crit_rate || 0) : 0
        crit_chance = CRIT_CHANCES[crit_stage] || "33.3%"
        crit_min = apply_modifiers(base_damage * 2, stab, effectiveness, 85)
        crit_max = apply_modifiers(base_damage * 2, stab, effectiveness, 100)

        {
          min: min_damage,
          max: max_damage,
          min_hits: hit_min,
          max_hits: hit_max,
          is_multi_hit: is_multi_hit,
          min_total: min_total,
          max_total: max_total,
          avg_total: avg_total,
          crit_min: crit_min,
          crit_max: crit_max,
          crit_stage: crit_stage,
          crit_chance: crit_chance,
          stab: stab,
          effectiveness: effectiveness,
          attacker_stat: atk_stat,
          defender_stat: def_stat
        }
      end

      # Runs calculate three times: current nature, best nature, worst nature.
      #
      # Returns: { current: <calc_result>, best: <calc_result_with_nature>, worst: <calc_result_with_nature> }
      def calculate_with_natures(attacker:, defender:, move:)
        move_record = resolve_move(move)
        category = move_record.category

        current_result = calculate(attacker: attacker, defender: defender, move: move_record)

        best_nature = best_nature_for(category)
        best_attacker = attacker.merge(nature: best_nature)
        best_result = calculate(attacker: best_attacker, defender: defender, move: move_record).merge(nature: best_nature)

        worst_nature = worst_nature_for(category)
        worst_attacker = attacker.merge(nature: worst_nature)
        worst_result = calculate(attacker: worst_attacker, defender: defender, move: move_record).merge(nature: worst_nature)

        { current: current_result, best: best_result, worst: worst_result }
      end

      private

      def resolve_move(move)
        return Pokemon::Move.find_by!(name: move[:name]) if move.is_a?(Hash)
        move
      end

      def stat_keys_for(category)
        case category
        when "physical" then [:atk, :def_stat]
        when "special"  then [:spa, :spd]
        end
      end

      def compute_stat(base_stat_record, stat_key, iv, ev, level, nature_name)
        base = base_stat_record.public_send(stat_key)
        modifier = nature_modifier(nature_name, stat_key)
        calculate_stat(base: base, iv: iv, ev: ev, level: level, nature_modifier: modifier)
      end

      def nature_modifier(nature_name, stat_key)
        return 1.0 if nature_name.nil?

        info = PixeldexHelper::NATURES[nature_name]
        return 1.0 if info.nil? || info[:up].nil?

        boosted_stat = NATURE_STAT_MAP[info[:up]]
        lowered_stat = NATURE_STAT_MAP[info[:down]]

        if stat_key == boosted_stat
          1.1
        elsif stat_key == lowered_stat
          0.9
        else
          1.0
        end
      end

      # Find the nature that maximizes the relevant attack stat for the given category.
      def best_nature_for(category)
        target_abbr = category == "physical" ? "Atk" : "SpA"
        # Pick a nature that boosts the attack stat. Among those, pick the first alphabetically for determinism.
        boosting = PixeldexHelper::NATURES.select { |_, info| info[:up] == target_abbr }
        boosting.keys.first
      end

      # Find the nature that minimizes the relevant attack stat for the given category.
      def worst_nature_for(category)
        target_abbr = category == "physical" ? "Atk" : "SpA"
        # Pick a nature that lowers the attack stat.
        lowering = PixeldexHelper::NATURES.select { |_, info| info[:down] == target_abbr }
        lowering.keys.first
      end

      def stab?(move_type, attacker_types)
        attacker_types.include?(move_type)
      end

      def explosion_move?(move_record)
        move_record.name.in?(%w[Explosion Self-Destruct])
      end

      # Apply modifiers in order: STAB, effectiveness, random roll. Floor after each.
      def apply_modifiers(base_damage, stab, effectiveness, roll)
        damage = base_damage

        # STAB
        if stab
          damage = (damage * 1.5).floor
        end

        # Type effectiveness
        damage = (damage * effectiveness).floor

        # Random roll
        damage = (damage * roll / 100)

        # Minimum 1 damage (unless immunity, handled before this is called)
        [damage, 1].max
      end

      def zero_result(stab: false, effectiveness: 0.0, attacker_stat: 0, defender_stat: 0)
        {
          min: 0, max: 0,
          min_total: 0, max_total: 0, avg_total: 0,
          min_hits: 1, max_hits: 1, is_multi_hit: false,
          crit_min: 0, crit_max: 0, crit_stage: 0, crit_chance: "6.25%",
          stab: stab, effectiveness: effectiveness,
          attacker_stat: attacker_stat, defender_stat: defender_stat
        }
      end
    end
  end
end
