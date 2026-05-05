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

  # Build JSON data for a location's groups (used in `data-groups` attributes
  # on each `.node` / `.special-cell`). Step 23 R4 extended the per-pokemon
  # payload so the JS-rendered EDIT button can mirror the dashboard's
  # `pixeldex#selectPokemon` dispatch without a separate helper. Additive
  # only — older readers (`buildDetailsHtml`'s legacy fields) still see
  # `species` / `player` / `sprite`.
  #
  # Per-group fields:
  #   id          — group.id (used as data-group-id on EDIT/MARK DEAD)
  #   nickname, status, caught_at, eulogy
  #   species_for_user — current_user's species in this group (or "")
  #   types_for_user   — comma-joined types of the current_user's species
  #   pokemon          — array of per-pokemon hashes (see below)
  #
  # Per-pokemon fields:
  #   id, is_mine, level, ability, nature, sprite_url, types
  #   species, player, sprite (legacy fields, retained)
  def groups_json_for(groups, current_user_id = nil)
    return "[]" if groups.blank?
    groups.map do |g|
      my_pokemon = g.soul_link_pokemon.find { |p| p.discord_user_id == current_user_id }
      {
        id: g.id,
        nickname: g.nickname,
        status: g.status,
        caught_at: g.caught_at&.strftime("%b %d"),
        eulogy: g.eulogy,
        species_for_user: my_pokemon&.species || "",
        types_for_user: my_pokemon&.species.present? ? SoulLink::GameState.types_for(my_pokemon.species).join(",") : "",
        pokemon: g.soul_link_pokemon.map do |p|
          sprite_filename = SoulLink::GameState.sprite_filename(p.species)
          sprite_url = p.species.present? && sprite_filename ? (ActionController::Base.helpers.asset_path("sprites/#{sprite_filename}.png") rescue nil) : nil
          {
            id: p.id,
            is_mine: p.discord_user_id == current_user_id,
            species: p.species,
            player: SoulLink::GameState.player_name(p.discord_user_id),
            player_name: SoulLink::GameState.player_name(p.discord_user_id),
            sprite: sprite_filename,
            sprite_url: sprite_url,
            level: p.level,
            ability: p.ability,
            nature: p.nature,
            types: p.species.present? ? SoulLink::GameState.types_for(p.species) : []
          }
        end
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

  # ── Step 23 R4 helpers ────────────────────────────────────────────────

  # Walks `progression["segments"]` in order, then the segment's
  # `locations` Array in order, and returns the FIRST loc_key whose
  # `location_status(groups_by_location[loc_key])` is `"uncaught"` AND
  # whose `loc_data["type"]` is `"route"`. Cities, dungeons, lakes, and
  # special encounters are intentionally skipped — the NOW pin only marks
  # the next route.
  #
  # Returns the loc_key string or `nil` when every route is caught/dead.
  def next_uncaught_route_key(progression, locations, groups_by_location)
    segments = progression["segments"] || []
    segments.each do |segment|
      (segment["locations"] || []).each do |loc_key|
        loc_data = locations[loc_key]
        next unless loc_data
        next unless loc_data["type"] == "route"
        next unless location_status(groups_by_location[loc_key]) == "uncaught"
        return loc_key
      end
    end
    nil
  end

  # Returns the bare-city label (e.g. `"VEILSTONE"`) for the segment that
  # contains `next_uncaught_key`. Source of truth: walks segments to find
  # the matching one, looks up its `gym` key in `gym_info`, takes that
  # gym's `location` (a loc_key like `veilstone_city`), strips the
  # `_city` / `_town` suffix, and uppercases.
  #
  # Returns `"FINAL STRETCH"` when `next_uncaught_key` is nil (every
  # route caught — late game).
  def current_segment_label(progression, gym_info, next_uncaught_key)
    return "FINAL STRETCH" if next_uncaught_key.blank?
    segments = progression["segments"] || []
    segment = segments.find { |s| (s["locations"] || []).include?(next_uncaught_key) }
    return "FINAL STRETCH" unless segment
    gym_key = segment["gym"]
    return "ELITE FOUR" if gym_key.blank?
    gym = gym_info[gym_key]
    return "FINAL STRETCH" unless gym
    bare_city_label(gym["location"])
  end

  # Returns the divider label that sits AFTER segment `seg_idx` (i.e.
  # before segment `seg_idx + 1`). Mockup pattern: divider labels name
  # the UPCOMING segment, e.g. between segment 1 and 2 the divider says
  # "ETERNA" because segment 2's gym is in Eterna.
  #
  # The final divider — before the null-gym (Victory Road / Elite Four)
  # segment — returns `"ELITE FOUR"` (Architect Q3 lock; mockup's `"…"`
  # was a truncation artifact). Returns `nil` when `seg_idx` points at
  # or past the last segment (no divider after the last segment).
  def segment_divider_label(progression, gym_info, seg_idx)
    segments = progression["segments"] || []
    next_seg = segments[seg_idx + 1]
    return nil unless next_seg
    gym_key = next_seg["gym"]
    return "ELITE FOUR" if gym_key.blank?
    gym = gym_info[gym_key]
    return "ELITE FOUR" unless gym
    bare_city_label(gym["location"])
  end

  # Returns `{ caught: N, total: M }` for a segment. Total counts only
  # CATCHABLE locations whose `loc_data["type"]` is `route`, `dungeon`,
  # `lake`, or `special` — cities and towns are excluded because most
  # have no tall grass and don't consume an encounter slot. Caught counts
  # those locations whose `location_status` is `"caught"` OR `"dead"`
  # (both consume the encounter slot). Architect Q4 lock.
  def segment_progress(segment, locations, groups_by_location)
    catchable_types = %w[route dungeon lake special]
    total = 0
    caught = 0
    (segment["locations"] || []).each do |loc_key|
      loc_data = locations[loc_key]
      next unless loc_data
      next unless catchable_types.include?(loc_data["type"])
      total += 1
      status = location_status(groups_by_location[loc_key])
      caught += 1 if status == "caught" || status == "dead"
    end
    { caught: caught, total: total }
  end

  # Returns true if the given segment contains the next-uncaught route
  # (i.e. the mobile accordion should server-render this segment with
  # the `open` attribute on its `<details>` element).
  def segment_open_by_default?(segment, next_uncaught_key)
    return false if next_uncaught_key.blank?
    (segment["locations"] || []).include?(next_uncaught_key)
  end

  # Returns the CSS class suffix for a node's `.glyph` based on the
  # location type and computed status. The mockup's `.node.special` style
  # only applies to uncaught specials — once a special is caught it gets
  # the standard `.caught` treatment (so the gift sprite shows in place
  # of the amber star).
  def node_status_class(loc_data, status)
    return "special" if loc_data && loc_data["type"] == "special" && status == "uncaught"
    status
  end

  private

  # Strips a trailing `_city` or `_town` from a loc_key and uppercases.
  # `eterna_city` → `"ETERNA"`, `solaceon_town` → `"SOLACEON"`.
  # Falls back to upcased loc_key if neither suffix is present.
  def bare_city_label(loc_key)
    return "" if loc_key.blank?
    base = loc_key.to_s.sub(/_city\z/, "").sub(/_town\z/, "")
    base.upcase
  end
end
