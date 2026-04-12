import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "tabContent", "tabButton",
    "pokemonDetail",
    "pokemonModal", "modalSprite", "modalSpeciesName", "modalNickLoc", "modalTypes",
    "modalSpeciesInput", "modalSpeciesHidden", "modalLevel", "modalAbility",
    "modalEvoInfo", "modalEvoText", "modalLinked", "modalNickname",
    "modalDeadBtn", "modalStatus", "modalPokemonId", "modalGroupId",
    "modalNature", "modalNatureLabel",
    "onTeamGrid", "storageGrid", "fallenGrid"
  ]

  static values = {
    abilitiesData: Object,
    evolutionsData: Object,
    spriteMap: Object,
    naturesData: Object,
    pokemonUpdateUrl: String,
    groupUpdateUrl: String,
    updateSlotsUrl: String,
    csrf: String
  }

  connect() {
    this.#initSortables()
  }

  // ── Sortable Initialization ──

  #initSortables() {
    const sortableOpts = {
      group: "pcbox",
      animation: 150,
      filter: ".empty",
      ghostClass: "sortable-ghost",
      dragClass: "sortable-drag",
      onEnd: (evt) => this.#onDragEnd(evt)
    }

    if (this.hasOnTeamGridTarget) {
      this.onTeamSortable = Sortable.create(this.onTeamGridTarget, { ...sortableOpts })
    }
    if (this.hasStorageGridTarget) {
      this.storageSortable = Sortable.create(this.storageGridTarget, { ...sortableOpts })
    }
    if (this.hasFallenGridTarget) {
      this.fallenSortable = Sortable.create(this.fallenGridTarget, { ...sortableOpts })
    }
  }

  async #onDragEnd(evt) {
    const item = evt.item
    const groupId = item.dataset.groupId
    if (!groupId) return

    const fromEl = evt.from
    const toEl = evt.to
    if (fromEl === toEl) {
      // Reorder within same section — only matters for ON TEAM
      if (toEl === this.onTeamGridTarget) {
        await this.#saveTeamSlots()
      }
      return
    }

    const fromSection = this.#sectionName(fromEl)
    const toSection = this.#sectionName(toEl)

    try {
      // Handle status transitions
      if (toSection === "fallen" && fromSection !== "fallen") {
        // Mark dead
        await this.#updateGroupStatus(groupId, "dead")
      } else if (fromSection === "fallen" && toSection !== "fallen") {
        // Revive
        await this.#updateGroupStatus(groupId, "caught")
      }

      // Handle team slot changes
      if (toSection === "onteam" || fromSection === "onteam") {
        // Enforce max 6
        if (toSection === "onteam") {
          const teamCards = this.onTeamGridTarget.querySelectorAll(".box-cell:not(.empty)")
          if (teamCards.length > 6) {
            // Bounce back — reload will fix state
            window.location.reload()
            return
          }
        }
        await this.#saveTeamSlots()
      }

      window.location.reload()
    } catch (error) {
      console.error("Drag operation failed:", error)
      window.location.reload()
    }
  }

  #sectionName(el) {
    if (this.hasOnTeamGridTarget && el === this.onTeamGridTarget) return "onteam"
    if (this.hasStorageGridTarget && el === this.storageGridTarget) return "storage"
    if (this.hasFallenGridTarget && el === this.fallenGridTarget) return "fallen"
    return "unknown"
  }

  async #updateGroupStatus(groupId, status) {
    const res = await fetch(`${this.groupUpdateUrlValue}/${groupId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
      body: JSON.stringify({ status })
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || "Status update failed")
    }
  }

  async #saveTeamSlots() {
    if (!this.hasOnTeamGridTarget || !this.updateSlotsUrlValue) return

    const cards = this.onTeamGridTarget.querySelectorAll(".box-cell:not(.empty)")
    const groupIds = Array.from(cards).map(c => c.dataset.groupId).filter(Boolean)

    const res = await fetch(this.updateSlotsUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
      body: JSON.stringify({ group_ids: groupIds })
    })
    if (!res.ok) {
      const data = await res.json()
      throw new Error(data.error || "Team update failed")
    }
  }

  // ── Tab Switching ──

  switchTab(event) {
    const tab = event.currentTarget.dataset.tab

    this.tabContentTargets.forEach(el => el.classList.add("hidden"))
    const target = this.tabContentTargets.find(el => el.dataset.tab === tab)
    if (target) target.classList.remove("hidden")

    this.tabButtonTargets.forEach(btn => {
      btn.classList.toggle("active", btn.dataset.tab === tab)
    })

    if (this.hasPokemonDetailTarget) {
      this.pokemonDetailTarget.classList.add("hidden")
      this.#clearSelected()
    }
  }

  // ── PC Box Cell Selection ──

  selectPokemon(event) {
    // Don't open modal if this was a drag
    if (event.currentTarget.classList.contains("sortable-chosen")) return

    const cell = event.currentTarget

    if (this.hasPokemonModalTarget) {
      this.#openModal(cell)
      return
    }

    if (!this.hasPokemonDetailTarget) return

    if (cell.classList.contains("selected")) {
      cell.classList.remove("selected")
      this.pokemonDetailTarget.classList.add("hidden")
      return
    }

    this.#clearSelected()
    cell.classList.add("selected")

    const detail = this.pokemonDetailTarget
    const nameEl = detail.querySelector("[data-detail-name]")
    const nickEl = detail.querySelector("[data-detail-nick]")
    const locEl = detail.querySelector("[data-detail-loc]")
    const typesEl = detail.querySelector("[data-detail-types]")
    const deadBtn = detail.querySelector("[data-detail-dead-btn]")
    const deadInfo = detail.querySelector("[data-detail-dead-info]")

    if (nameEl) nameEl.textContent = (cell.dataset.groupSpecies || "").toUpperCase()
    if (nickEl) nickEl.textContent = `"${cell.dataset.groupNickname || ""}"`
    if (locEl) locEl.textContent = cell.dataset.groupLocation || ""
    if (typesEl) typesEl.innerHTML = this.#renderTypeBadges(cell.dataset.groupTypes)

    if (cell.dataset.groupStatus === "dead") {
      if (deadBtn) deadBtn.classList.add("hidden")
      if (deadInfo) { deadInfo.classList.remove("hidden"); deadInfo.textContent = "FALLEN" }
    } else {
      if (deadBtn) {
        deadBtn.classList.remove("hidden")
        deadBtn.dataset.groupId = cell.dataset.groupId
        deadBtn.dataset.groupNickname = cell.dataset.groupNickname
      }
      if (deadInfo) deadInfo.classList.add("hidden")
    }

    detail.classList.remove("hidden")
  }

  // ── Pokemon Modal ──

  #openModal(cell) {
    const species = cell.dataset.groupSpecies || ""
    const nickname = cell.dataset.groupNickname || ""
    const location = cell.dataset.groupLocation || ""
    const status = cell.dataset.groupStatus || "caught"
    const groupId = cell.dataset.groupId || ""
    const pokemonData = cell.dataset.groupPokemon ? JSON.parse(cell.dataset.groupPokemon) : []

    const myPokemon = pokemonData.find(p => p.is_mine) || {}

    this.modalSpeciesNameTarget.textContent = species.toUpperCase() || "UNASSIGNED"
    this.modalNickLocTarget.textContent = `"${nickname}" @ ${location}`
    this.modalTypesTarget.innerHTML = this.#renderTypeBadges(cell.dataset.groupTypes)

    if (species && this.spriteMapValue[species]) {
      this.modalSpriteTarget.innerHTML =
        `<img src="${this.spriteMapValue[species]}" width="72" height="72" style="image-rendering: pixelated;">`
    } else {
      this.modalSpriteTarget.innerHTML = '<span style="font-size: 24px; color: var(--d2);">?</span>'
    }

    this.modalSpeciesInputTarget.value = species
    this.modalSpeciesHiddenTarget.value = species
    this.modalLevelTarget.value = myPokemon.level || ""
    this.#populateAbilities(species, myPokemon.ability || "")
    this.#populateEvolution(species)
    this.modalNatureTarget.value = myPokemon.nature || ""
    this.#updateNatureLabelFromValue(myPokemon.nature || "")
    this.modalNicknameTarget.value = nickname
    this.#populateLinked(pokemonData)
    this.modalPokemonIdTarget.value = myPokemon.id || ""
    this.modalGroupIdTarget.value = groupId

    if (status === "dead") {
      this.modalDeadBtnTarget.classList.add("hidden")
    } else {
      this.modalDeadBtnTarget.classList.remove("hidden")
      this.modalDeadBtnTarget.dataset.groupId = groupId
      this.modalDeadBtnTarget.dataset.groupNickname = nickname
    }

    this.modalStatusTarget.textContent = ""
    this.pokemonModalTarget.classList.remove("hidden")
  }

  closePokemonModal() {
    this.pokemonModalTarget.classList.add("hidden")
  }

  searchSpecies() {
    const input = this.modalSpeciesInputTarget.value.trim()

    if (this.abilitiesDataValue[input] || this.evolutionsDataValue[input] !== undefined) {
      this.modalSpeciesHiddenTarget.value = input
      this.#populateAbilities(input, "")
      this.#populateEvolution(input)
      this.modalSpeciesNameTarget.textContent = input.toUpperCase()

      if (this.spriteMapValue[input]) {
        this.modalSpriteTarget.innerHTML =
          `<img src="${this.spriteMapValue[input]}" width="72" height="72" style="image-rendering: pixelated;">`
      }
    }
  }

  async savePokemon() {
    const pokemonId = this.modalPokemonIdTarget.value
    const groupId = this.modalGroupIdTarget.value
    const species = this.modalSpeciesHiddenTarget.value || this.modalSpeciesInputTarget.value.trim()
    const level = this.modalLevelTarget.value ? parseInt(this.modalLevelTarget.value) : null
    const ability = this.modalAbilityTarget.value || null
    const nature = this.modalNatureTarget.value || null
    const nickname = this.modalNicknameTarget.value.trim()

    this.modalStatusTarget.textContent = "SAVING..."

    try {
      if (pokemonId) {
        // Update existing pokemon
        const pokemonRes = await fetch(`${this.pokemonUpdateUrlValue}/${pokemonId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
          body: JSON.stringify({ species, level, ability, nature })
        })

        if (!pokemonRes.ok) {
          const data = await pokemonRes.json()
          this.modalStatusTarget.textContent = data.error || "SAVE FAILED"
          return
        }
      } else if (species && groupId) {
        // Create new pokemon record for this user in the group
        const createRes = await fetch(this.pokemonUpdateUrlValue, {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
          body: JSON.stringify({ group_id: groupId, species, level, ability, nature })
        })

        if (!createRes.ok) {
          const data = await createRes.json()
          this.modalStatusTarget.textContent = data.error || "SAVE FAILED"
          return
        }
      }

      if (groupId && nickname) {
        const groupRes = await fetch(`${this.groupUpdateUrlValue}/${groupId}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
          body: JSON.stringify({ nickname })
        })

        if (!groupRes.ok) {
          const data = await groupRes.json()
          this.modalStatusTarget.textContent = data.error || "SAVE FAILED"
          return
        }
      }

      window.location.reload()
    } catch (error) {
      this.modalStatusTarget.textContent = "NETWORK ERROR"
    }
  }

  updateNatureLabel() {
    this.#updateNatureLabelFromValue(this.modalNatureTarget.value)
  }

  // ── Private Helpers ──

  #updateNatureLabelFromValue(nature) {
    if (!this.hasModalNatureLabelTarget) return
    const info = this.naturesDataValue[nature]
    if (!info || !info.up) {
      this.modalNatureLabelTarget.textContent = nature ? "Neutral" : ""
    } else {
      this.modalNatureLabelTarget.textContent = `+${info.up}  -${info.down}`
    }
  }

  #populateAbilities(species, currentAbility) {
    const abilities = this.abilitiesDataValue[species] || []
    const select = this.modalAbilityTarget
    select.innerHTML = '<option value="">Select...</option>'

    abilities.forEach(ab => {
      const opt = document.createElement("option")
      opt.value = ab
      opt.textContent = ab
      if (ab === currentAbility) opt.selected = true
      select.appendChild(opt)
    })
  }

  #buildEvolutionChain(species) {
    const data = this.evolutionsDataValue
    if (!data[species]) return []

    // Walk backward to find the base form (cap at 5 to prevent infinite loops)
    const ancestors = []
    let current = species
    for (let i = 0; i < 5; i++) {
      let parent = null
      for (const [name, entry] of Object.entries(data)) {
        if (entry.evolves_to === current) {
          parent = name
          break
        }
      }
      if (!parent) break
      ancestors.unshift(parent)
      current = parent
    }

    // Build chain: ancestors + selected species + forward walk
    const chain = []

    // Add ancestors with trigger info from their entries
    for (let i = 0; i < ancestors.length; i++) {
      const entry = data[ancestors[i]]
      if (i === 0) {
        chain.push({ name: ancestors[i], level: null, method: null })
      } else {
        const prev = data[ancestors[i - 1]]
        chain.push({ name: ancestors[i], level: prev.level || null, method: prev.method || null })
      }
    }

    // Add the selected species
    const prevName = ancestors.length > 0 ? ancestors[ancestors.length - 1] : null
    const prevEntry = prevName ? data[prevName] : null
    chain.push({
      name: species,
      level: prevEntry ? (prevEntry.level || null) : null,
      method: prevEntry ? (prevEntry.method || null) : null
    })

    // Walk forward from species (cap at 5 total chain length)
    current = species
    for (let i = chain.length; i < 5; i++) {
      const entry = data[current]
      if (!entry || !entry.evolves_to) break
      chain.push({
        name: entry.evolves_to,
        level: entry.level || null,
        method: entry.method || null
      })
      current = entry.evolves_to
    }

    return chain
  }

  #populateEvolution(species) {
    const chain = this.#buildEvolutionChain(species)

    if (chain.length === 0) {
      this.modalEvoInfoTarget.classList.add("hidden")
      this.modalEvoTextTarget.replaceChildren()
      return
    }

    this.modalEvoInfoTarget.classList.remove("hidden")
    const container = this.modalEvoTextTarget
    container.replaceChildren()

    chain.forEach((entry, index) => {
      // Add arrow separator between entries
      if (index > 0) {
        const sep = document.createElement("span")
        sep.textContent = " → "
        sep.style.color = "var(--d2)"
        container.appendChild(sep)
      }

      // Species name — bold + accent color if currently selected
      const nameEl = document.createElement(entry.name === species ? "strong" : "span")
      nameEl.textContent = entry.name
      nameEl.style.color = entry.name === species ? "var(--a1)" : "var(--d2)"
      container.appendChild(nameEl)

      // Trigger info (level or method) for non-base entries
      if (entry.level) {
        const lvl = document.createElement("span")
        lvl.textContent = ` Lv.${entry.level}`
        lvl.style.fontSize = "9px"
        lvl.style.color = "var(--d2)"
        container.appendChild(lvl)
      } else if (entry.method) {
        const mth = document.createElement("span")
        mth.textContent = ` (${entry.method})`
        mth.style.fontSize = "9px"
        mth.style.color = "var(--d2)"
        container.appendChild(mth)
      }
    })
  }

  #populateLinked(pokemonData) {
    const container = this.modalLinkedTarget
    container.innerHTML = ""

    if (!pokemonData.length) {
      container.innerHTML = '<div style="font-size: 10px; color: var(--d2); padding: 4px 0;">No linked pokemon data</div>'
      return
    }

    const naturesData = this.naturesDataValue || {}

    pokemonData.forEach(p => {
      const card = document.createElement("div")
      card.style.cssText = "border: var(--border-thin); padding: 6px 8px; margin-bottom: 4px; font-size: 10px;"
      if (p.is_mine) card.style.borderWidth = "3px"

      // Player name row
      const nameRow = document.createElement("div")
      nameRow.style.cssText = "display: flex; align-items: center; justify-content: space-between; margin-bottom: 4px;"
      const nameSpan = document.createElement("span")
      nameSpan.textContent = p.player_name
      if (p.is_mine) nameSpan.style.fontWeight = "bold"
      nameRow.appendChild(nameSpan)

      if (p.is_mine) {
        const youBadge = document.createElement("span")
        youBadge.textContent = "YOU"
        youBadge.className = "type-text"
        youBadge.style.cssText = "font-size: 8px; background: var(--d2); color: var(--l2); border-color: var(--d1);"
        nameRow.appendChild(youBadge)
      }
      card.appendChild(nameRow)

      if (p.species) {
        // Species + sprite row
        const speciesRow = document.createElement("div")
        speciesRow.style.cssText = "display: flex; align-items: center; gap: 4px; margin-bottom: 3px;"
        if (p.sprite_url) {
          speciesRow.innerHTML = `<img src="${p.sprite_url}" width="20" height="20" style="image-rendering: pixelated;"> `
        }
        const specName = document.createElement("span")
        specName.textContent = p.species
        speciesRow.appendChild(specName)
        card.appendChild(speciesRow)

        // Stats row: level, ability, nature
        const stats = []
        if (p.level) stats.push(`Lv.${p.level}`)
        if (p.ability) stats.push(p.ability)
        if (p.nature) {
          const info = naturesData[p.nature]
          const effect = (info && info.up) ? ` (+${info.up} -${info.down})` : ""
          stats.push(`${p.nature}${effect}`)
        }

        if (stats.length) {
          const statsRow = document.createElement("div")
          statsRow.style.cssText = "font-size: 9px; color: var(--d2);"
          statsRow.textContent = stats.join(" / ")
          card.appendChild(statsRow)
        }
      } else {
        const unassigned = document.createElement("div")
        unassigned.textContent = "(unassigned)"
        unassigned.style.cssText = "color: var(--d2); font-style: italic;"
        card.appendChild(unassigned)
      }

      container.appendChild(card)
    })
  }

  #renderTypeBadges(typesStr) {
    if (!typesStr) return ""
    const abbrevs = {
      "Normal": "NRM", "Fire": "FIR", "Water": "WTR", "Electric": "ELC",
      "Grass": "GRS", "Ice": "ICE", "Fighting": "FGT", "Poison": "PSN",
      "Ground": "GND", "Flying": "FLY", "Psychic": "PSY", "Bug": "BUG",
      "Rock": "RCK", "Ghost": "GHO", "Dragon": "DRG", "Dark": "DRK", "Steel": "STL"
    }
    return typesStr.split(",").filter(Boolean).map(t =>
      `<span class="type-text">${abbrevs[t.trim()] || t.trim()}</span>`
    ).join(" ")
  }

  #clearSelected() {
    this.element.querySelectorAll(".box-cell.selected").forEach(el => {
      el.classList.remove("selected")
    })
  }
}
