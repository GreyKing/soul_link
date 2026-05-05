import { Controller } from "@hotwired/stimulus"

// Step 23 R4 — extended for the standalone /map redesign.
// Targets renamed `panel*` → `sheet*`; `backdrop` removed. New
// targets `emptyState`, `groupList`, `jumpBtn`, `accordionSegment`.
// New actions: `jumpToNow`, `showCatchFormForCurrent`. Hash sync:
// `#route=<key>` is read in `connect()` and written in
// `selectLocation`; cleared in `closePanel`. All existing actions
// (`submitCatch`, `toggleGym`, `filterSpecies`, `selectSpecies`,
// `closeAllDropdowns`, `handleKeydown`, `scrollToCurrentProgress`)
// are preserved.
export default class extends Controller {
  static targets = [
    "scrollContainer", "track", "locationNode",
    "sheet", "sheetTitle", "sheetBody", "sheetForm",
    "emptyState", "groupList", "jumpBtn", "accordionSegment",
    "formLocationKey", "nicknameInput", "formStatus",
    "speciesSearchWrapper", "speciesHidden", "speciesDropdown", "speciesPreview"
  ]

  static values = {
    gymsDefeated: Number,
    csrf: String,
    gymProgressUrl: String,
    createGroupUrl: String,
    pokedexSpecies: Array,
    spriteMap: Object
  }

  connect() {
    this._handleKeydown = this.handleKeydown.bind(this)
    this._closeAllDropdowns = this.closeAllDropdowns.bind(this)
    document.addEventListener("keydown", this._handleKeydown)
    document.addEventListener("click", this._closeAllDropdowns)

    // Hide the JUMP TO NOW button if no `.next` node exists (every
    // route caught — late game). Always-on otherwise.
    if (this.hasJumpBtnTarget) {
      const hasNext = this.locationNodeTargets.some(n => n.classList.contains("next"))
      if (!hasNext) this.jumpBtnTarget.classList.add("hidden")
    }

    this.scrollToCurrentProgress()

    // `#route=<key>` URL hash → re-open the sheet on that route.
    // Step 22 precedent (`pc_box_filter_controller.js`). Wrapped in
    // requestAnimationFrame so the sheet markup is laid out before
    // we synthesize the click.
    this.applyHashRoute()
  }

  disconnect() {
    document.removeEventListener("keydown", this._handleKeydown)
    document.removeEventListener("click", this._closeAllDropdowns)
  }

  // ── Hash sync ─────────────────────────────────────────────────────

  applyHashRoute() {
    const hash = window.location.hash.replace(/^#/, "")
    if (!hash.startsWith("route=")) return
    const key = hash.slice("route=".length)
    if (!key) return
    const node = this.locationNodeTargets.find(n => n.dataset.locationKey === key)
    if (!node) return
    requestAnimationFrame(() => this._openSheetFromNode(node))
  }

  // ── Timeline: Auto-scroll to first uncaught ──────────────────────

  scrollToCurrentProgress() {
    // Restore scroll position after catch submission reload
    const savedScroll = sessionStorage.getItem("timeline-scroll")
    if (savedScroll) {
      sessionStorage.removeItem("timeline-scroll")
      if (this.hasScrollContainerTarget) {
        this.scrollContainerTarget.scrollLeft = parseInt(savedScroll, 10)
      }
      return
    }

    // Otherwise scroll to first uncaught location
    const firstUncaught = this.locationNodeTargets.find(
      n => n.dataset.status === "uncaught"
    )
    if (firstUncaught && this.hasScrollContainerTarget) {
      requestAnimationFrame(() => {
        firstUncaught.scrollIntoView({
          behavior: "smooth",
          block: "nearest",
          inline: "center"
        })
      })
    }
  }

  // ── Location Click → Open Sheet ──────────────────────────────────

  selectLocation(event) {
    event.stopPropagation()
    const node = event.currentTarget
    this._openSheetFromNode(node)
    // Write hash so refresh / share-link survives.
    const key = node.dataset.locationKey
    if (key) {
      history.replaceState(null, "", "#route=" + encodeURIComponent(key))
    }
  }

  _openSheetFromNode(node) {
    const key = node.dataset.locationKey
    const name = node.dataset.locationName
    let groups = []
    try { groups = JSON.parse(node.dataset.groups || "[]") } catch (_) {}

    this.highlightNode(node)

    if (this.hasSheetTitleTarget) this.sheetTitleTarget.textContent = name || key

    if (groups.length === 0) {
      this._renderSheetCatchForm(key, name)
    } else {
      this._renderSheetGroupList(key, name, groups)
    }
  }

  highlightNode(node) {
    // Drop highlight from every node, then add to the clicked one.
    this.locationNodeTargets.forEach(n => {
      n.classList.remove("selected")
    })
    node.classList.add("selected")
  }

  // ── Sheet rendering ──────────────────────────────────────────────

  closePanel() {
    if (this.hasGroupListTarget) {
      this.groupListTarget.classList.add("hidden")
      this.groupListTarget.innerHTML = ""
    }
    if (this.hasSheetFormTarget) {
      this.sheetFormTarget.classList.add("hidden")
      this.resetForm()
    }
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.remove("hidden")
    }
    if (this.hasSheetTitleTarget) {
      this.sheetTitleTarget.textContent = "Select a route"
    }

    // Clear hash without touching scroll.
    if (window.location.hash.startsWith("#route=")) {
      history.replaceState(null, "", window.location.pathname + window.location.search)
    }

    // Drop selection highlight.
    this.locationNodeTargets.forEach(n => n.classList.remove("selected"))
  }

  _renderSheetCatchForm(key, name) {
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
    if (this.hasGroupListTarget) {
      this.groupListTarget.classList.add("hidden")
      this.groupListTarget.innerHTML = ""
    }
    if (!this.hasSheetFormTarget) {
      // Read-only mode — no form available. Show a quiet message
      // in the group list area.
      if (this.hasGroupListTarget) {
        this.groupListTarget.classList.remove("hidden")
        this.groupListTarget.innerHTML = `
          <div class="empty-state" style="color: var(--l1);">
            No catches recorded for ${this._escape(name || key)}.
            This run is read-only — new catches cannot be logged.
          </div>`
      }
      return
    }
    this.sheetFormTarget.classList.remove("hidden")
    if (this.hasFormLocationKeyTarget) this.formLocationKeyTarget.value = key
    if (this.hasNicknameInputTarget) {
      requestAnimationFrame(() => this.nicknameInputTarget.focus())
    }
  }

  _renderSheetGroupList(key, name, groups) {
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
    if (this.hasSheetFormTarget) this.sheetFormTarget.classList.add("hidden")
    if (!this.hasGroupListTarget) return

    const readOnly = !this.hasSheetFormTarget
    const cardsHtml = [...groups].reverse().map(g => this._buildGroupCardHtml(g, readOnly)).join("")
    const dupesBtnHtml = readOnly ? "" : `
      <button type="button"
              class="dupes-btn"
              data-action="click->timeline#showCatchFormForCurrent"
              data-location-key="${this._escape(key)}">
        + ANOTHER ENCOUNTER (DUPES CLAUSE)
      </button>`

    const aliveCount = groups.filter(g => g.status === "caught").length
    const statusPill = aliveCount > 0
      ? `<span class="pill">CAUGHT</span>`
      : `<span class="pill dead">DEAD</span>`

    this.groupListTarget.innerHTML = `
      <div class="sheet-status">
        ${statusPill}
        ${groups.length} group${groups.length === 1 ? "" : "s"} &middot; ${this._escape(name || key)}
      </div>
      ${cardsHtml}
      ${dupesBtnHtml}
    `
    this.groupListTarget.classList.remove("hidden")

    // The form's location-key needs to track the selected route so
    // the dupes-clause button can swap to form mode in place.
    if (this.hasFormLocationKeyTarget) this.formLocationKeyTarget.value = key
  }

  _buildGroupCardHtml(group, readOnly) {
    const isDead = group.status === "dead"
    const cardClass = isDead ? "group-card dead" : "group-card"
    const pillText = isDead ? "DEAD" : "ALIVE"

    const playerRows = (group.pokemon || []).map(p => {
      const sprite = p.sprite_url
        ? `<img src="${this._escape(p.sprite_url)}" alt="${this._escape(p.species || "")}" width="24" height="24" style="image-rendering: pixelated;" loading="lazy" onerror="this.style.display='none'">`
        : "&mdash;"
      const speciesText = p.species
        ? `${this._escape(p.species)}${p.level ? " &middot; Lv " + Number(p.level) : ""}`
        : "&mdash;"
      const playerName = p.player_name || p.player || ""
      return `
        <div class="player-row">
          <span class="pname">${this._escape(playerName.toString().toUpperCase())}</span>
          <div class="pinput">
            <span class="preview">${sprite}</span>
            <span style="font-size: 14px; color: var(--white);">${speciesText}</span>
          </div>
        </div>`
    }).join("")

    const myPokemon = (group.pokemon || []).find(p => p.is_mine) || {}
    const types = group.types_for_user || ""
    const pokemonJson = this._escape(JSON.stringify(group.pokemon || []))

    const actionsHtml = readOnly ? "" : `
      <div class="actions">
        <button type="button"
                class="submit-btn muted"
                data-action="click->pixeldex#selectPokemon"
                data-group-id="${group.id}"
                data-group-nickname="${this._escape(group.nickname || "")}"
                data-group-species="${this._escape(group.species_for_user || "")}"
                data-group-location="${this._escape(group.location || "")}"
                data-group-status="${this._escape(group.status || "caught")}"
                data-group-types="${this._escape(types)}"
                data-group-pokemon="${pokemonJson}">EDIT</button>
        <button type="button"
                class="submit-btn danger"
                data-action="click->dashboard#openMarkDeadModal"
                data-group-id="${group.id}"
                data-group-nickname="${this._escape(group.nickname || "")}">MARK DEAD</button>
      </div>`

    return `
      <div class="${cardClass}">
        <div class="head">
          <span class="nickname">${this._escape((group.nickname || "").toString().toUpperCase())}</span>
          <span class="pill">${pillText}</span>
        </div>
        ${playerRows}
        ${actionsHtml}
      </div>`
  }

  // Shows the catch form in place of the group-list (dupes-clause flow).
  showCatchFormForCurrent(event) {
    event.stopPropagation()
    if (!this.hasSheetFormTarget) return
    const key = event.currentTarget.dataset.locationKey
    if (this.hasGroupListTarget) this.groupListTarget.classList.add("hidden")
    this.sheetFormTarget.classList.remove("hidden")
    if (key && this.hasFormLocationKeyTarget) this.formLocationKeyTarget.value = key
    if (this.hasNicknameInputTarget) {
      requestAnimationFrame(() => this.nicknameInputTarget.focus())
    }
  }

  // ── JUMP TO NOW ──────────────────────────────────────────────────

  jumpToNow(event) {
    if (event) event.stopPropagation()
    const next = this.locationNodeTargets.find(n => n.classList.contains("next"))
    if (!next) return
    next.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "center" })
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.closePanel()
    }
  }

  resetForm() {
    if (!this.hasSheetFormTarget) return
    const form = this.sheetFormTarget
    if (form && form.tagName === "FORM") form.reset()
    this.speciesHiddenTargets.forEach(h => (h.value = ""))
    this.speciesPreviewTargets.forEach(p => (p.innerHTML = ""))
    if (this.hasFormStatusTarget) {
      this.formStatusTarget.textContent = ""
    }
  }

  // ── Species Search/Autocomplete (preserved) ─────────────────────

  filterSpecies(event) {
    const input = event.target
    const query = input.value.toLowerCase().trim()
    const wrapper = input.closest("[data-timeline-target='speciesSearchWrapper']")
    if (!wrapper) return
    const dropdown = wrapper.querySelector("[data-timeline-target='speciesDropdown']")
    if (!dropdown) return

    if (query.length < 1) {
      dropdown.classList.add("hidden")
      return
    }

    const startsWith = []
    const includes = []
    for (const species of this.pokedexSpeciesValue) {
      const lower = species.toLowerCase()
      if (lower.startsWith(query)) {
        startsWith.push(species)
      } else if (lower.includes(query)) {
        includes.push(species)
      }
      if (startsWith.length + includes.length >= 20) break
    }
    const matches = [...startsWith, ...includes].slice(0, 20)

    if (matches.length === 0) {
      dropdown.innerHTML = `<div>No species found</div>`
    } else {
      dropdown.innerHTML = matches
        .map(species => `
          <div data-action="click->timeline#selectSpecies"
               data-species="${this._escape(species)}">${this._escape(species)}</div>`)
        .join("")
    }

    dropdown.classList.remove("hidden")
  }

  selectSpecies(event) {
    event.stopPropagation()
    const species = event.currentTarget.dataset.species
    const wrapper = event.currentTarget.closest("[data-timeline-target='speciesSearchWrapper']")
    if (!wrapper) return
    const input = wrapper.querySelector("input[type='text']")
    const hidden = wrapper.querySelector("[data-timeline-target='speciesHidden']")
    const dropdown = wrapper.querySelector("[data-timeline-target='speciesDropdown']")
    const preview = wrapper.querySelector("[data-timeline-target='speciesPreview']")

    if (input) input.value = species
    if (hidden) hidden.value = species
    if (dropdown) dropdown.classList.add("hidden")

    if (preview) {
      const file = this.getSpriteFilename(species)
      preview.innerHTML = file
        ? `<img src="/assets/sprites/${file}.png" alt="${this._escape(species)}" width="24" height="24" style="image-rendering: pixelated;" loading="lazy" onerror="this.style.display='none'">`
        : "&mdash;"
    }
  }

  getSpriteFilename(species) {
    return this.spriteMapValue[species] || ""
  }

  closeAllDropdowns(event) {
    if (!event.target.closest("[data-timeline-target='speciesSearchWrapper']")) {
      this.speciesDropdownTargets.forEach(d => d.classList.add("hidden"))
    }
  }

  // ── Form Submission (preserved) ─────────────────────────────────

  async submitCatch(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)

    if (this.hasFormStatusTarget) {
      this.formStatusTarget.textContent = "Saving..."
    }

    if (this.hasScrollContainerTarget) {
      sessionStorage.setItem("timeline-scroll", this.scrollContainerTarget.scrollLeft)
    }

    try {
      const response = await fetch(this.createGroupUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfValue,
          Accept: "application/json"
        },
        body: formData
      })

      if (response.ok) {
        if (this.hasFormStatusTarget) this.formStatusTarget.textContent = "Saved!"
        setTimeout(() => window.location.reload(), 500)
      } else {
        const data = await response.json().catch(() => ({}))
        const msg = data.error || "Save failed"
        if (this.hasFormStatusTarget) this.formStatusTarget.textContent = msg
      }
    } catch (error) {
      if (this.hasFormStatusTarget) this.formStatusTarget.textContent = "Network error"
    }
  }

  // ── Gym Toggle (preserved) ──────────────────────────────────────

  async toggleGym(event) {
    event.stopPropagation()
    const gymNumber = parseInt(event.currentTarget.dataset.gymNumber)

    try {
      const response = await fetch(this.gymProgressUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ gym_number: gymNumber })
      })

      if (response.ok) {
        const data = await response.json()
        this.gymsDefeatedValue = data.gyms_defeated
        if (this.hasScrollContainerTarget) {
          sessionStorage.setItem("timeline-scroll", this.scrollContainerTarget.scrollLeft)
        }
        setTimeout(() => window.location.reload(), 300)
      }
    } catch (error) {
      console.error("Failed to toggle gym:", error)
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────

  // Minimal HTML-attr escape — for templated strings that may carry
  // user-entered nicknames. Stimulus values pre-escaped server-side
  // would be cleaner, but the JS-only group-card path needs a small
  // safety net.
  _escape(value) {
    if (value == null) return ""
    return value.toString()
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }
}
