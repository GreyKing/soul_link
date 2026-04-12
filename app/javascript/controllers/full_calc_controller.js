import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "attackerSpecies", "attackerLevel", "attackerNature", "attackerSprite", "attackerTypes", "attackerStats", "attackerQuickPick",
    "defenderSpecies", "defenderLevel", "defenderNature", "defenderSprite", "defenderTypes", "defenderStats", "defenderQuickPick",
    "moveSelect", "moveInfo",
    "resultSection",
    "historySection", "historyList"
  ]
  static values = { csrf: String, pokemonUrl: String, calcUrl: String, teamPokemon: Array }

  connect() {
    this._attackerMoves = []
    this._attackerData = null
    this._defenderData = null
    this._history = []
    this._lastAttackerSpecies = null
    this._lastDefenderSpecies = null

    // Build valid species set from datalist for input validation
    const datalist = document.getElementById("full-calc-species")
    this._validSpecies = new Set()
    if (datalist) {
      for (const opt of datalist.options) {
        this._validSpecies.add(opt.value)
      }
    }

    this._renderQuickPicks(this.attackerQuickPickTarget, "attacker")
    this._renderQuickPicks(this.defenderQuickPickTarget, "defender")
  }

  // ── Quick-pick button rendering ──

  _renderQuickPicks(container, side) {
    container.replaceChildren()
    this.teamPokemonValue.forEach(pkmn => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.textContent = `${pkmn.species} Lv.${pkmn.level}`
      btn.style.cssText = "font-size: 9px; padding: 2px 6px; border: var(--border-thin); cursor: pointer; background: var(--d1); color: var(--l2);"
      btn.addEventListener("mouseenter", () => { btn.style.background = "var(--d2)" })
      btn.addEventListener("mouseleave", () => { btn.style.background = "var(--d1)" })
      btn.addEventListener("click", () => this._quickPick(side, pkmn))
      container.appendChild(btn)
    })
  }

  _quickPick(side, pkmn) {
    if (side === "attacker") {
      this.attackerSpeciesTarget.value = pkmn.species
      this.attackerLevelTarget.value = pkmn.level
      this.attackerNatureTarget.value = pkmn.nature || ""
      this._lastAttackerSpecies = null
      this.attackerChanged()
    } else {
      this.defenderSpeciesTarget.value = pkmn.species
      this.defenderLevelTarget.value = pkmn.level
      this.defenderNatureTarget.value = pkmn.nature || ""
      this._lastDefenderSpecies = null
      this.defenderChanged()
    }
  }

  // ── Attacker changed ──

  attackerChanged() {
    const species = this.attackerSpeciesTarget.value.trim()
    if (!species || species === this._lastAttackerSpecies) return
    // Only fetch if species matches a datalist option (avoids partial-type fetches)
    if (!this._isValidSpecies(species)) return
    this._lastAttackerSpecies = species

    this._fetchPokemon(species).then(data => {
      if (!data) {
        this._resetMoveSelect()
        this.moveInfoTarget.textContent = ""
        this._attackerMoves = []
        this._attackerData = null
        this._clearSide("attacker")
        return
      }

      this._attackerData = data
      this._populateSide("attacker", data)
      this._attackerMoves = data.moves || []
      this._populateMoves(this._attackerMoves)

      // Auto-calculate if defender and move are set
      if (this.moveSelectTarget.value && this._defenderData) {
        this.calculate()
      }
    })
  }

  // ── Defender changed ──

  defenderChanged() {
    const species = this.defenderSpeciesTarget.value.trim()
    if (!species || species === this._lastDefenderSpecies) return
    if (!this._isValidSpecies(species)) return
    this._lastDefenderSpecies = species

    this._fetchPokemon(species).then(data => {
      if (!data) {
        this._defenderData = null
        this._clearSide("defender")
        return
      }

      this._defenderData = data
      this._populateSide("defender", data)

      // Auto-calculate if attacker and move are set
      if (this.moveSelectTarget.value && this._attackerData) {
        this.calculate()
      }
    })
  }

  // ── Move changed ──

  moveChanged() {
    const moveName = this.moveSelectTarget.value
    if (!moveName) {
      this.moveInfoTarget.textContent = ""
      this.resultSectionTarget.classList.add("hidden")
      return
    }

    const move = this._attackerMoves.find(m => m.name === moveName)
    if (move) {
      this.moveInfoTarget.textContent = `${move.type} | ${move.category} | Power: ${move.power || "\u2014"}`
    }

    this.calculate()
  }

  // ── Calculate damage ──

  async calculate() {
    const attackerSpecies = this.attackerSpeciesTarget.value.trim()
    const defenderSpecies = this.defenderSpeciesTarget.value.trim()
    const moveName = this.moveSelectTarget.value
    if (!attackerSpecies || !defenderSpecies || !moveName) return

    const body = {
      attacker_species: attackerSpecies,
      attacker_level: parseInt(this.attackerLevelTarget.value, 10) || 50,
      attacker_nature: this.attackerNatureTarget.value || null,
      defender_species: defenderSpecies,
      defender_level: parseInt(this.defenderLevelTarget.value, 10) || 50,
      defender_nature: this.defenderNatureTarget.value || null,
      move_name: moveName
    }

    try {
      const response = await fetch(this.calcUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify(body)
      })

      if (!response.ok) {
        this.resultSectionTarget.textContent = "Calculation failed."
        this.resultSectionTarget.classList.remove("hidden")
        return
      }

      const result = await response.json()
      this._displayResult(result)
      this._addToHistory(attackerSpecies, defenderSpecies, moveName, result, body)
    } catch (e) {
      this.resultSectionTarget.textContent = "Calculation error."
      this.resultSectionTarget.classList.remove("hidden")
    }
  }

  // ── Swap attacker and defender ──

  swap() {
    // Save current values
    const atkSpecies = this.attackerSpeciesTarget.value
    const atkLevel = this.attackerLevelTarget.value
    const atkNature = this.attackerNatureTarget.value
    const defSpecies = this.defenderSpeciesTarget.value
    const defLevel = this.defenderLevelTarget.value
    const defNature = this.defenderNatureTarget.value

    // Swap field values
    this.attackerSpeciesTarget.value = defSpecies
    this.attackerLevelTarget.value = defLevel
    this.attackerNatureTarget.value = defNature
    this.defenderSpeciesTarget.value = atkSpecies
    this.defenderLevelTarget.value = atkLevel
    this.defenderNatureTarget.value = atkNature

    // Swap cached data
    const tmpData = this._attackerData
    this._attackerData = this._defenderData
    this._defenderData = tmpData

    // Re-render sides from cached data
    if (this._attackerData) {
      this._populateSide("attacker", this._attackerData)
    } else {
      this._clearSide("attacker")
    }
    if (this._defenderData) {
      this._populateSide("defender", this._defenderData)
    } else {
      this._clearSide("defender")
    }

    // Clear move dropdown and re-fetch new attacker's moves
    this._resetMoveSelect()
    this.moveInfoTarget.textContent = ""
    this.resultSectionTarget.classList.add("hidden")
    this._attackerMoves = []

    if (this._attackerData) {
      this._attackerMoves = this._attackerData.moves || []
      this._populateMoves(this._attackerMoves)
    }
  }

  // ── History ──

  _addToHistory(attacker, defender, moveName, result, body) {
    const entry = { attacker, defender, moveName, result, body }
    this._history.unshift(entry)
    if (this._history.length > 5) this._history.pop()

    this._renderHistory()
  }

  _renderHistory() {
    this.historyListTarget.replaceChildren()

    if (this._history.length === 0) {
      this.historySectionTarget.classList.add("hidden")
      return
    }

    this.historySectionTarget.classList.remove("hidden")

    this._history.forEach((entry, index) => {
      const row = document.createElement("div")
      row.style.cssText = "padding: 3px 6px; border: var(--border-thin); margin-bottom: 2px; cursor: pointer; font-size: 10px; color: var(--l1);"
      row.textContent = `${entry.attacker} \u2192 ${entry.defender}: ${entry.moveName} (${entry.result.min}-${entry.result.max})`
      row.addEventListener("mouseenter", () => { row.style.background = "var(--d2)" })
      row.addEventListener("mouseleave", () => { row.style.background = "" })
      row.addEventListener("click", () => this._loadFromHistory(entry))
      this.historyListTarget.appendChild(row)
    })
  }

  _isValidSpecies(species) {
    return this._validSpecies && this._validSpecies.has(species)
  }

  _loadFromHistory(entry) {
    const b = entry.body
    this.attackerSpeciesTarget.value = b.attacker_species
    this.attackerLevelTarget.value = b.attacker_level
    this.attackerNatureTarget.value = b.attacker_nature || ""
    this.defenderSpeciesTarget.value = b.defender_species
    this.defenderLevelTarget.value = b.defender_level
    this.defenderNatureTarget.value = b.defender_nature || ""

    // Re-fetch both sides and then set the move
    Promise.all([
      this._fetchPokemon(b.attacker_species),
      this._fetchPokemon(b.defender_species)
    ]).then(([atkData, defData]) => {
      if (atkData) {
        this._attackerData = atkData
        this._populateSide("attacker", atkData)
        this._attackerMoves = atkData.moves || []
        this._populateMoves(this._attackerMoves)
      }
      if (defData) {
        this._defenderData = defData
        this._populateSide("defender", defData)
      }

      // Set the move and re-calculate
      this.moveSelectTarget.value = b.move_name
      this.moveChanged()
    })
  }

  // ── Private helpers ──

  async _fetchPokemon(species) {
    try {
      const url = this.pokemonUrlValue + encodeURIComponent(species)
      const response = await fetch(url, {
        headers: { "X-CSRF-Token": this.csrfValue }
      })
      if (!response.ok) return null
      return await response.json()
    } catch (e) {
      return null
    }
  }

  _populateSide(side, data) {
    const spriteTarget = side === "attacker" ? this.attackerSpriteTarget : this.defenderSpriteTarget
    const typesTarget = side === "attacker" ? this.attackerTypesTarget : this.defenderTypesTarget
    const statsTarget = side === "attacker" ? this.attackerStatsTarget : this.defenderStatsTarget

    // Sprite
    spriteTarget.replaceChildren()
    if (data.sprite_url) {
      const img = document.createElement("img")
      img.alt = data.species
      img.width = 48
      img.height = 48
      img.style.imageRendering = "pixelated"
      img.src = data.sprite_url
      spriteTarget.appendChild(img)
    }

    // Types
    typesTarget.replaceChildren()
    ;(data.types || []).forEach(t => {
      const span = document.createElement("span")
      span.classList.add("type-text")
      span.textContent = this._typeAbbr(t)
      typesTarget.appendChild(span)
      typesTarget.appendChild(document.createTextNode(" "))
    })

    // Stats
    const s = data.stats
    if (s) {
      statsTarget.textContent =
        `HP:${s.hp} ATK:${s.atk} DEF:${s.def} SPA:${s.spa} SPD:${s.spd} SPE:${s.spe}`
    }
  }

  _clearSide(side) {
    const spriteTarget = side === "attacker" ? this.attackerSpriteTarget : this.defenderSpriteTarget
    const typesTarget = side === "attacker" ? this.attackerTypesTarget : this.defenderTypesTarget
    const statsTarget = side === "attacker" ? this.attackerStatsTarget : this.defenderStatsTarget

    spriteTarget.replaceChildren()
    typesTarget.textContent = ""
    statsTarget.textContent = ""
  }

  _resetMoveSelect() {
    const select = this.moveSelectTarget
    select.replaceChildren()
    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = "Select a move..."
    select.appendChild(placeholder)
  }

  _populateMoves(moves) {
    this._resetMoveSelect()
    const select = this.moveSelectTarget
    moves.forEach(m => {
      const opt = document.createElement("option")
      opt.value = m.name
      opt.textContent = `${m.name} (${this._typeAbbr(m.type)}, ${m.category}, ${m.power || "\u2014"})`
      select.appendChild(opt)
    })
    this.moveInfoTarget.textContent = ""
  }

  _displayResult(r) {
    const section = this.resultSectionTarget
    section.replaceChildren()
    section.classList.remove("hidden")

    const lines = []

    lines.push(this._makeResultLine("Per Hit:", `${r.min} - ${r.max}`))

    if (r.is_multi_hit) {
      lines.push(this._makeResultLine("Total:", `${r.min_total} - ${r.max_total} (${r.min_hits}-${r.max_hits} hits)`))
      lines.push(this._makeResultLine("Average:", `${r.avg_total}`))
    }

    lines.push(this._makeResultLine("Crit:", `${r.crit_min} - ${r.crit_max}`))

    // Info line: STAB, effectiveness, crit chance
    const infoParts = []
    if (r.stab) infoParts.push("STAB \u2713")
    infoParts.push(this._effectivenessLabel(r.effectiveness))
    infoParts.push(`Crit Chance: ${r.crit_chance}`)

    const infoDiv = document.createElement("div")
    infoDiv.style.cssText = "font-size: 10px; margin-top: 6px; display: flex; gap: 8px; flex-wrap: wrap;"

    infoParts.forEach(part => {
      const span = document.createElement("span")
      span.textContent = part

      if (part.startsWith("STAB")) {
        span.style.color = "var(--d1)"
      } else if (part.includes("4x")) {
        span.style.color = "#e55"
      } else if (part.includes("2x")) {
        span.style.color = "#e93"
      } else if (part.includes("0.5x") || part.includes("0.25x")) {
        span.style.color = "#58f"
      } else if (part.includes("0x")) {
        span.style.color = "var(--d2)"
      }

      infoDiv.appendChild(span)
    })

    // Stat summary line
    const statSummary = document.createElement("div")
    statSummary.style.cssText = "font-size: 9px; color: var(--d2); margin-top: 6px;"
    const summaryParts = []
    if (r.attacker_stat) summaryParts.push(`Attacker: ${r.attacker_stat}`)
    if (r.defender_stat) summaryParts.push(`Defender: ${r.defender_stat}`)
    statSummary.textContent = summaryParts.join("  |  ")

    lines.forEach(el => section.appendChild(el))
    section.appendChild(infoDiv)
    if (summaryParts.length > 0) section.appendChild(statSummary)
  }

  _makeResultLine(label, value) {
    const div = document.createElement("div")
    div.style.cssText = "display: flex; justify-content: space-between; font-size: 11px; padding: 2px 0;"

    const labelSpan = document.createElement("span")
    labelSpan.style.color = "var(--d2)"
    labelSpan.textContent = label

    const valueSpan = document.createElement("span")
    valueSpan.textContent = value

    div.appendChild(labelSpan)
    div.appendChild(valueSpan)
    return div
  }

  _effectivenessLabel(eff) {
    if (eff === 0) return "Immune (0x)"
    if (eff === 0.25) return "Not very effective (0.25x)"
    if (eff === 0.5) return "Not very effective (0.5x)"
    if (eff === 1) return "Neutral (1x)"
    if (eff === 2) return "Super Effective (2x)"
    if (eff === 4) return "Super Effective (4x)"
    return `${eff}x`
  }

  _typeAbbr(typeName) {
    const map = {
      "Normal": "NRM", "Fire": "FIR", "Water": "WTR", "Electric": "ELC",
      "Grass": "GRS", "Ice": "ICE", "Fighting": "FGT", "Poison": "PSN",
      "Ground": "GND", "Flying": "FLY", "Psychic": "PSY", "Bug": "BUG",
      "Rock": "RCK", "Ghost": "GHO", "Dragon": "DRG", "Dark": "DRK", "Steel": "STL"
    }
    return map[typeName] || typeName.substring(0, 3).toUpperCase()
  }
}
