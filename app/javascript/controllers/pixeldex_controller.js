import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "tabContent", "tabButton",
    "pokemonDetail",
    "pokemonModal", "modalSprite", "modalSpeciesName", "modalNickLoc", "modalTypes",
    "modalSpeciesInput", "modalSpeciesHidden", "modalLevel", "modalAbility", "modalAbilityLabel",
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
    abilityEffectsData: Object,
    pokemonUpdateUrl: String,
    groupUpdateUrl: String,
    updateSlotsUrl: String,
    csrf: String
  }

  connect() {
    this.#initSortables()
    this.#applyHashTab()
  }

  // ── Step 24 R1 — Tablist keyboard support ──
  //
  // Bound at the dashboard tab-bar via `keydown->pixeldex#tablistKeydown`.
  // Implements the WAI-ARIA tablist pattern: ←/→ moves focus AND activates
  // the tab (mockup spec — unlike the spec's recommendation, the mockup
  // calls for instant activation rather than focus-only); Home/End jump
  // to the first/last tab. The 1-8 numeric jump is bound on `window`
  // (`numericJump`) so it works from anywhere on the page, except when
  // the user is typing in an input.

  tablistKeydown(event) {
    const buttons = this.tabButtonTargets
    if (buttons.length === 0) return

    const currentIndex = buttons.indexOf(document.activeElement)
    if (currentIndex === -1) return

    let targetIndex = null
    switch (event.key) {
      case "ArrowRight":
        targetIndex = (currentIndex + 1) % buttons.length
        break
      case "ArrowLeft":
        targetIndex = (currentIndex - 1 + buttons.length) % buttons.length
        break
      case "Home":
        targetIndex = 0
        break
      case "End":
        targetIndex = buttons.length - 1
        break
      default:
        return
    }

    event.preventDefault()
    const target = buttons[targetIndex]
    target.focus()
    target.click()
  }

  numericJump(event) {
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return

    const target = event.target
    if (target) {
      const tag = target.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return
      if (target.isContentEditable) return
    }

    const num = parseInt(event.key, 10)
    if (!Number.isInteger(num) || num < 1 || num > this.tabButtonTargets.length) return

    event.preventDefault()
    const button = this.tabButtonTargets[num - 1]
    if (button) {
      button.focus()
      button.click()
    }
  }

  // ── Hash-driven tab restore ──
  //
  // After a server redirect like `redirect_to root_path(anchor: "gyms")`,
  // the page reloads on the default tab and loses the user's tab state.
  // Reading window.location.hash on connect and clicking the matching
  // tab button replays the existing switchTab flow without bespoke logic.

  #applyHashTab() {
    const hash = window.location.hash.replace(/^#/, "")
    if (!hash) return
    const btn = this.tabButtonTargets.find(b => b.dataset.tab === hash)
    if (btn) btn.click()
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

    // Step 24 R1 — flip ARIA + tabindex on every tab button. Keep the
    // legacy `.active` class toggle for any rule that still relies on it.
    this.tabButtonTargets.forEach(btn => {
      const isActive = btn.dataset.tab === tab
      btn.classList.toggle("active", isActive)
      if (btn.hasAttribute("role") && btn.getAttribute("role") === "tab") {
        btn.setAttribute("aria-selected", isActive ? "true" : "false")
        btn.setAttribute("tabindex", isActive ? "0" : "-1")
      }
    })

    // Step 24 R1 — sync URL hash so a refresh restores the active tab.
    // `replaceState` matches Step 23's `#route=` precedent — no back-stack
    // pollution. Browsers without history API (none of our targets) will
    // simply skip this branch.
    if (typeof window !== "undefined" && window.history && window.history.replaceState) {
      window.history.replaceState(null, "", "#" + tab)
    }

    if (this.hasPokemonDetailTarget) {
      this.pokemonDetailTarget.classList.add("hidden")
      this.#clearSelected()
    }
  }

  // ── PC Box Cell Selection ──

  selectPokemon(event) {
    // A drag ends with a click on the dragged element; ignore it so dropping
    // into the party does not also open the detail modal. Complements the
    // existing sortable-chosen check below (the cloned box-cell does not
    // carry that class, so both guards are needed).
    if (document.body.classList.contains("sortable-dragging")) return

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

    this.modalSpriteTarget.replaceChildren()
    if (species && this.spriteMapValue[species]) {
      const img = document.createElement("img")
      img.src = this.spriteMapValue[species]
      img.width = 72
      img.height = 72
      img.style.imageRendering = "pixelated"
      this.modalSpriteTarget.appendChild(img)
    } else {
      const fallback = document.createElement("span")
      fallback.style.fontSize = "24px"
      fallback.style.color = "var(--d2)"
      fallback.textContent = "?"
      this.modalSpriteTarget.appendChild(fallback)
    }

    this.modalSpeciesInputTarget.value = species
    this.modalSpeciesHiddenTarget.value = species
    this.modalLevelTarget.value = myPokemon.level || ""

    // Track whether the current modal pokemon is eligible to evolve.
    // Mirrors the dead-btn gate so evolve buttons render only for live, owned pokemon.
    // Must be set before #populateEvolution so the renderer can read it.
    this.modalCanEvolve = status !== "dead" && Boolean(myPokemon.id)

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

  // The dimming backdrop sits *behind* the centering wrapper (both z-index
  // auto, wrapper paints later), so clicks in the empty area never reach it.
  // The wrapper carries the close action instead; this guard ignores clicks
  // that bubbled up from the modal card.
  closePokemonModalOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.closePokemonModal()
  }

  searchSpecies() {
    const input = this.modalSpeciesInputTarget.value.trim()

    if (this.abilitiesDataValue[input] || this.evolutionsDataValue[input] !== undefined) {
      this.modalSpeciesHiddenTarget.value = input
      this.#populateAbilities(input, "")
      this.#populateEvolution(input)
      this.modalSpeciesNameTarget.textContent = input.toUpperCase()

      if (this.spriteMapValue[input]) {
        this.modalSpriteTarget.replaceChildren()
        const img = document.createElement("img")
        img.src = this.spriteMapValue[input]
        img.width = 72
        img.height = 72
        img.style.imageRendering = "pixelated"
        this.modalSpriteTarget.appendChild(img)
      }
    }
  }

  async savePokemon(event) {
    const pokemonId = this.modalPokemonIdTarget.value
    const groupId = this.modalGroupIdTarget.value
    const species = this.modalSpeciesHiddenTarget.value || this.modalSpeciesInputTarget.value.trim()
    const level = this.modalLevelTarget.value ? parseInt(this.modalLevelTarget.value) : null
    const ability = this.modalAbilityTarget.value || null
    const nature = this.modalNatureTarget.value || null
    const nickname = this.modalNicknameTarget.value.trim()

    // Disable the SAVE button while the request is in flight so a double-click
    // can't fire 2-3 PATCHes in parallel (last-write-wins race).
    const saveBtn = event?.currentTarget
    if (saveBtn) saveBtn.disabled = true
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
          if (saveBtn) saveBtn.disabled = false
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
          if (saveBtn) saveBtn.disabled = false
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
          if (saveBtn) saveBtn.disabled = false
          return
        }
      }

      // Success path — reload destroys the page state, so leave the button
      // disabled (no point re-enabling something that's about to be torn down).
      window.location.reload()
    } catch (error) {
      this.modalStatusTarget.textContent = "NETWORK ERROR"
      if (saveBtn) saveBtn.disabled = false
    }
  }

  async evolvePokemon(event) {
    const pokemonId = this.modalPokemonIdTarget.value
    if (!pokemonId) return

    const targetSpecies = event.currentTarget.dataset.targetSpecies
    if (!targetSpecies) return

    // Disable the EVOLVE button + show loading text. Re-enable on error so
    // the player can retry; success path reloads the page.
    const evolveBtn = event.currentTarget
    evolveBtn.disabled = true
    const originalText = evolveBtn.textContent
    evolveBtn.textContent = "EVOLVING..."
    this.modalStatusTarget.textContent = "EVOLVING..."

    try {
      const res = await fetch(`${this.pokemonUpdateUrlValue}/${pokemonId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
        body: JSON.stringify({ species: targetSpecies })
      })

      if (!res.ok) {
        const data = await res.json()
        this.modalStatusTarget.textContent = data.error || "EVOLVE FAILED"
        evolveBtn.disabled = false
        evolveBtn.textContent = originalText
        return
      }

      window.location.reload()
    } catch (error) {
      this.modalStatusTarget.textContent = "NETWORK ERROR"
      evolveBtn.disabled = false
      evolveBtn.textContent = originalText
    }
  }

  updateNatureLabel() {
    this.#updateNatureLabelFromValue(this.modalNatureTarget.value)
  }

  updateAbilityLabel() {
    this.#updateAbilityLabelFromValue(this.modalAbilityTarget.value)
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

  #updateAbilityLabelFromValue(ability) {
    if (!this.hasModalAbilityLabelTarget) return
    const label = this.modalAbilityLabelTarget
    const effect = this.abilityEffectsDataValue?.[ability]
    if (!ability || !effect) {
      label.textContent = ""
      label.removeAttribute("data-ability-full")
    } else {
      label.textContent = effect.short || ""
      if (effect.full) {
        label.setAttribute("data-ability-full", effect.full)
      } else {
        label.removeAttribute("data-ability-full")
      }
    }
  }

  // Any Pokemon may now have any ability, so this no longer filters by
  // species — it just seeds the searchable select's current value. Kept
  // under the original name/arity because both callers (#openModal and
  // searchSpecies) still invoke it.
  #populateAbilities(_species, currentAbility) {
    this.modalAbilityTarget.value = currentAbility || ""

    const wrapper = this.modalAbilityTarget.closest(".searchable-select")
    const input = wrapper?.querySelector("[data-searchable-select-target='input']")
    if (input) input.value = currentAbility || ""

    this.#updateAbilityLabelFromValue(currentAbility || "")
  }

  // Builds a tree structure from evolutions data.
  // Returns { name, trigger: {level, method}, children: [], isSelected, onActivePath }
  // or null if species is not in the data.
  #buildEvolutionTree(species) {
    const data = this.evolutionsDataValue
    if (!data[species] && !this.#findParentOf(species)) return null

    // Walk backward to find the root (base form)
    let root = species
    for (let i = 0; i < 5; i++) {
      const parent = this.#findParentOf(root)
      if (!parent) break
      root = parent
    }

    // Build full tree from root forward
    const tree = this.#buildNode(root, { level: null, method: null }, species)

    // Mark the active path (from root to selected species)
    this.#markActivePath(tree, species)

    return tree
  }

  #findParentOf(speciesName) {
    const data = this.evolutionsDataValue
    for (const [name, entry] of Object.entries(data)) {
      if (!entry.evolves_to) continue
      if (entry.evolves_to.some(e => e.species === speciesName)) return name
    }
    return null
  }

  #buildNode(name, trigger, selectedSpecies) {
    const data = this.evolutionsDataValue
    const entry = data[name]
    const children = []
    if (entry && entry.evolves_to) {
      for (const branch of entry.evolves_to) {
        children.push(this.#buildNode(
          branch.species,
          { level: branch.level || null, method: branch.method || null },
          selectedSpecies
        ))
      }
    }
    return {
      name,
      trigger,
      children,
      isSelected: name === selectedSpecies,
      onActivePath: false
    }
  }

  // Recursively mark all nodes on the path from root to selected species
  #markActivePath(node, selectedSpecies) {
    if (node.name === selectedSpecies) {
      node.onActivePath = true
      return true
    }
    for (const child of node.children) {
      if (this.#markActivePath(child, selectedSpecies)) {
        node.onActivePath = true
        return true
      }
    }
    return false
  }

  #populateEvolution(species) {
    const tree = this.#buildEvolutionTree(species)

    if (!tree) {
      this.modalEvoInfoTarget.classList.add("hidden")
      this.modalEvoTextTarget.replaceChildren()
      return
    }

    this.modalEvoInfoTarget.classList.remove("hidden")
    const container = this.modalEvoTextTarget
    container.replaceChildren()

    this.#renderEvoNode(container, tree, species, true, false)
  }

  #renderEvoNode(container, node, selectedSpecies, isFirst, parentIsSelected = false) {
    // Arrow before this node (unless first in its line)
    if (!isFirst) {
      const sep = document.createElement("span")
      sep.textContent = " → "
      sep.style.color = "var(--d2)"
      container.appendChild(sep)
    }

    // Species name
    const nameEl = document.createElement(node.isSelected ? "strong" : "span")
    nameEl.textContent = node.name
    nameEl.style.color = node.onActivePath ? "var(--a1)" : "var(--d3)"
    if (!node.onActivePath) nameEl.style.opacity = "0.5"
    container.appendChild(nameEl)

    // Trigger info (level or method)
    if (node.trigger.level) {
      const lvl = document.createElement("span")
      lvl.textContent = ` Lv.${node.trigger.level}`
      lvl.style.fontSize = "9px"
      lvl.style.color = node.onActivePath ? "var(--d2)" : "var(--d3)"
      if (!node.onActivePath) lvl.style.opacity = "0.5"
      container.appendChild(lvl)
    } else if (node.trigger.method) {
      const mth = document.createElement("span")
      mth.textContent = ` (${node.trigger.method})`
      mth.style.fontSize = "9px"
      mth.style.color = node.onActivePath ? "var(--d2)" : "var(--d3)"
      if (!node.onActivePath) mth.style.opacity = "0.5"
      container.appendChild(mth)
    }

    // Evolve button — only on direct evolution targets of the currently-selected species,
    // and only when the modal pokemon is alive and owned by the current user.
    if (parentIsSelected && this.modalCanEvolve && this.modalPokemonIdTarget.value) {
      const evolveBtn = document.createElement("button")
      evolveBtn.type = "button"
      evolveBtn.className = "gb-btn-primary gb-btn-sm"
      evolveBtn.dataset.action = "click->pixeldex#evolvePokemon"
      evolveBtn.dataset.targetSpecies = node.name
      evolveBtn.style.fontSize = "9px"
      evolveBtn.style.padding = "2px 6px"
      evolveBtn.style.marginLeft = "4px"
      evolveBtn.textContent = "EVOLVE"
      container.appendChild(evolveBtn)
    }

    // Children
    if (node.children.length === 1) {
      // Linear — continue on same line
      this.#renderEvoNode(container, node.children[0], selectedSpecies, false, node.isSelected)
    } else if (node.children.length > 1) {
      // Branching — stack vertically with indent
      const branchContainer = document.createElement("div")
      branchContainer.style.marginLeft = "12px"
      branchContainer.style.borderLeft = "1px solid var(--d3)"
      branchContainer.style.paddingLeft = "8px"
      branchContainer.style.marginTop = "2px"

      for (const child of node.children) {
        const branchLine = document.createElement("div")
        branchLine.style.margin = "1px 0"
        this.#renderEvoNode(branchLine, child, selectedSpecies, false, node.isSelected)
        branchContainer.appendChild(branchLine)
      }
      container.appendChild(branchContainer)
    }
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
          const img = document.createElement("img")
          img.src = p.sprite_url
          img.width = 20
          img.height = 20
          img.style.imageRendering = "pixelated"
          speciesRow.appendChild(img)
          speciesRow.appendChild(document.createTextNode(" "))
        }
        const specName = document.createElement("span")
        specName.textContent = p.species
        speciesRow.appendChild(specName)
        card.appendChild(speciesRow)

        // Stats row: level, ability (with effect blurb), nature
        const statsRow = document.createElement("div")
        statsRow.style.cssText = "font-size: 9px; color: var(--d2);"
        const parts = []
        if (p.level) parts.push(document.createTextNode(`Lv.${p.level}`))
        if (p.ability) {
          const effect = this.abilityEffectsDataValue?.[p.ability]
          const abilitySpan = document.createElement("span")
          abilitySpan.textContent = effect?.short ? `${p.ability} (${effect.short})` : p.ability
          if (effect?.full) {
            abilitySpan.setAttribute("data-ability-full", effect.full)
            abilitySpan.style.cursor = "help"
          }
          parts.push(abilitySpan)
        }
        if (p.nature) {
          const info = naturesData[p.nature]
          const effect = (info && info.up) ? ` (+${info.up} -${info.down})` : ""
          parts.push(document.createTextNode(`${p.nature}${effect}`))
        }

        if (parts.length) {
          parts.forEach((node, i) => {
            if (i > 0) statsRow.appendChild(document.createTextNode(" / "))
            statsRow.appendChild(node)
          })
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
