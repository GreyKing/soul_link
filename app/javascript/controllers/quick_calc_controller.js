import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "defenderName", "defenderSprite", "defenderTypes", "defenderStats",
    "attackerSpecies", "attackerLevel", "attackerNature",
    "moveSelect", "moveInfo",
    "resultSection"
  ]
  static values = { csrf: String, pokemonUrl: String, calcUrl: String }

  connect() {
    this._attackerMoves = []
    this._defenderSpecies = null
    this._defenderLevel = 50
    this._defenderNature = null
    this._lastAttackerSpecies = null

    const datalist = document.getElementById("calc-species-list")
    this._validSpecies = new Set()
    if (datalist) {
      for (const opt of datalist.options) {
        this._validSpecies.add(opt.value)
      }
    }
  }

  // ── Open modal with defender pre-filled ──

  open(event) {
    event.preventDefault()
    event.stopPropagation()

    const btn = event.currentTarget
    this._defenderSpecies = btn.dataset.species
    this._defenderLevel = parseInt(btn.dataset.level, 10) || 50
    this._defenderNature = btn.dataset.nature || null

    // Reset attacker fields
    this.attackerSpeciesTarget.value = ""
    this.attackerLevelTarget.value = 50
    this.attackerNatureTarget.value = ""
    this._resetMoveSelect()
    this.moveInfoTarget.textContent = ""
    this.resultSectionTarget.classList.add("hidden")
    this.resultSectionTarget.textContent = ""
    this._attackerMoves = []

    // Fetch defender data
    this._fetchPokemon(this._defenderSpecies).then(data => {
      if (!data) return
      this._populateDefender(data)
      this.modalTarget.classList.remove("hidden")
      this.modalTarget.focus()
    })
  }

  close() {
    this.modalTarget.classList.add("hidden")
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  // ── Attacker changed ──

  attackerChanged() {
    const species = this.attackerSpeciesTarget.value.trim()
    if (!species || species === this._lastAttackerSpecies) return
    if (!(this._validSpecies && this._validSpecies.has(species))) return
    this._lastAttackerSpecies = species

    this._fetchPokemon(species).then(data => {
      if (!data) {
        this._resetMoveSelect()
        this.moveInfoTarget.textContent = ""
        this._attackerMoves = []
        return
      }

      this._attackerMoves = data.moves || []
      this._populateMoves(this._attackerMoves)
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
      this.moveInfoTarget.textContent = `${move.type} | ${move.category} | Power: ${move.power || "—"}`
    }

    this.calculate()
  }

  // ── Calculate damage ──

  async calculate() {
    const attackerSpecies = this.attackerSpeciesTarget.value.trim()
    const moveName = this.moveSelectTarget.value
    if (!attackerSpecies || !moveName || !this._defenderSpecies) return

    const body = {
      attacker_species: attackerSpecies,
      attacker_level: parseInt(this.attackerLevelTarget.value, 10) || 50,
      attacker_nature: this.attackerNatureTarget.value || null,
      defender_species: this._defenderSpecies,
      defender_level: this._defenderLevel,
      defender_nature: this._defenderNature,
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
    } catch (e) {
      this.resultSectionTarget.textContent = "Calculation error."
      this.resultSectionTarget.classList.remove("hidden")
    }
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

  _populateDefender(data) {
    this.defenderNameTarget.textContent = data.species

    // Build sprite img from server-provided URL
    this.defenderSpriteTarget.replaceChildren()
    if (data.sprite_url) {
      const img = document.createElement("img")
      img.alt = data.species
      img.width = 48
      img.height = 48
      img.classList.add("inline-block")
      img.style.imageRendering = "pixelated"
      img.src = data.sprite_url
      this.defenderSpriteTarget.appendChild(img)
    }

    // Types
    this.defenderTypesTarget.textContent = ""
    data.types.forEach(t => {
      const span = document.createElement("span")
      span.classList.add("type-text")
      span.textContent = this._typeAbbr(t)
      this.defenderTypesTarget.appendChild(span)
      this.defenderTypesTarget.appendChild(document.createTextNode(" "))
    })

    // Stats
    const s = data.stats
    this.defenderStatsTarget.textContent =
      `HP:${s.hp} ATK:${s.atk} DEF:${s.def} SPA:${s.spa} SPD:${s.spd} SPE:${s.spe}`
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
      opt.textContent = `${m.name} (${this._typeAbbr(m.type)}, ${m.category}, ${m.power || "—"})`
      select.appendChild(opt)
    })
    this.moveInfoTarget.textContent = ""
    this.resultSectionTarget.classList.add("hidden")
  }

  _displayResult(r) {
    const section = this.resultSectionTarget
    section.textContent = ""
    section.classList.remove("hidden")

    const lines = []

    lines.push(this._makeResultLine("Damage:", `${r.min} - ${r.max}`))

    if (r.is_multi_hit) {
      lines.push(this._makeResultLine("Total:", `${r.min_total} - ${r.max_total} (${r.min_hits}-${r.max_hits} hits)`))
      lines.push(this._makeResultLine("Average:", `${r.avg_total}`))
    }

    lines.push(this._makeResultLine("Crit:", `${r.crit_min} - ${r.crit_max}`))

    // Info line
    const infoParts = []
    if (r.stab) infoParts.push("STAB")
    infoParts.push(this._effectivenessLabel(r.effectiveness))
    infoParts.push(`Crit Chance: ${r.crit_chance}`)

    const infoDiv = document.createElement("div")
    infoDiv.style.cssText = "font-size: 10px; margin-top: 6px; display: flex; gap: 8px; flex-wrap: wrap;"

    infoParts.forEach(part => {
      const span = document.createElement("span")
      span.textContent = part

      if (part === "STAB") {
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

    lines.forEach(el => section.appendChild(el))
    section.appendChild(infoDiv)
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
