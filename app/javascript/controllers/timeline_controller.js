import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "scrollContainer", "track", "locationNode",
    "panel", "panelTitle", "panelBody", "panelForm", "backdrop",
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
    this.scrollToCurrentProgress()
  }

  disconnect() {
    document.removeEventListener("keydown", this._handleKeydown)
    document.removeEventListener("click", this._closeAllDropdowns)
  }

  // ── Timeline: Auto-scroll to first uncaught ──

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

  // ── Location Click → Open Panel ──

  selectLocation(event) {
    event.stopPropagation()
    const node = event.currentTarget
    const key = node.dataset.locationKey
    const name = node.dataset.locationName
    const status = node.dataset.status

    // Highlight selected node
    this.highlightNode(node)

    if (status === "uncaught") {
      this.openPanelWithForm(key, name)
    } else {
      this.openPanelWithDetails(key, name, node)
    }
  }

  highlightNode(node) {
    // Remove previous highlight
    this.locationNodeTargets.forEach(n => {
      const circle = n.querySelector(".timeline-node")
      if (circle) {
        circle.classList.remove("ring-2", "ring-indigo-400", "ring-offset-2", "ring-offset-gray-800")
      }
    })
    // Add highlight to selected
    const circle = node.querySelector(".timeline-node")
    if (circle) {
      circle.classList.add("ring-2", "ring-indigo-400", "ring-offset-2", "ring-offset-gray-800")
    }
  }

  // ── Slide-Out Panel ──

  openPanel() {
    this.panelTarget.classList.remove("translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden", "sm:overflow-auto")
  }

  closePanel() {
    this.panelTarget.classList.add("translate-x-full")
    this.panelTarget.classList.remove("translate-x-0")
    this.backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden", "sm:overflow-auto")
    this.resetForm()

    // Remove node highlights
    this.locationNodeTargets.forEach(n => {
      const circle = n.querySelector(".timeline-node")
      if (circle) {
        circle.classList.remove("ring-2", "ring-indigo-400", "ring-offset-2", "ring-offset-gray-800")
      }
    })
  }

  openPanelWithForm(key, name) {
    this.panelTitleTarget.textContent = name
    this.panelBodyTarget.innerHTML = `
      <p class="text-gray-400 text-sm">No catch yet at this location.</p>
    `
    this.panelFormTarget.classList.remove("hidden")
    this.formLocationKeyTarget.value = key
    this.openPanel()
    requestAnimationFrame(() => this.nicknameInputTarget.focus())
  }

  openPanelWithDetails(key, name, node) {
    this.panelTitleTarget.textContent = name

    // Parse groups from data attribute
    let groups = []
    try { groups = JSON.parse(node.dataset.groups || "[]") } catch (_) {}

    this.panelBodyTarget.innerHTML = this.buildDetailsHtml(groups)

    // Show form for "Add Another Catch"
    this.panelFormTarget.classList.remove("hidden")
    this.panelFormTarget.querySelector("h3").textContent = groups.length > 0 ? "Add Another Catch" : "New Catch"
    this.formLocationKeyTarget.value = key
    this.openPanel()
  }

  buildDetailsHtml(groups) {
    if (!groups || groups.length === 0) {
      return '<p class="text-gray-500 text-sm">No catches recorded.</p>'
    }

    return groups.map(group => {
      const isDead = group.status === "dead"
      const statusBadge = isDead
        ? '<span class="text-xs text-red-400 font-medium">💀 Dead</span>'
        : '<span class="text-xs text-green-400 font-medium">✓ Caught</span>'

      let pokemonHtml = ""
      if (group.pokemon && group.pokemon.length > 0) {
        pokemonHtml = group.pokemon.map(p => {
          const spriteHtml = p.sprite
            ? `<img src="/assets/sprites/${p.sprite}.png" alt="${p.species}" width="24" height="24" class="inline-block" loading="lazy" onerror="this.style.display='none'">`
            : ""
          return `
            <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-gray-700/50">
              ${spriteHtml}
              <div>
                <div class="text-sm font-medium text-white">${p.species}</div>
                <div class="text-xs text-gray-400">${p.player}</div>
              </div>
            </div>
          `
        }).join("")
      } else {
        pokemonHtml = '<span class="text-xs text-gray-500">No species assigned yet</span>'
      }

      return `
        <div class="mb-4 pb-4 border-b border-gray-700 last:border-0 last:mb-0 last:pb-0">
          <div class="flex items-center justify-between mb-2">
            <span class="text-base font-semibold ${isDead ? 'text-red-300' : 'text-white'}">${group.nickname}</span>
            ${statusBadge}
          </div>
          ${group.caught_at ? `<div class="text-xs text-gray-500 mb-2">Caught: ${group.caught_at}</div>` : ""}
          ${group.eulogy ? `<div class="text-xs text-gray-400 italic mb-2">"${group.eulogy}"</div>` : ""}
          <div class="grid gap-2">
            ${pokemonHtml}
          </div>
        </div>
      `
    }).join("")
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.closePanel()
    }
  }

  resetForm() {
    const form = this.panelFormTarget.querySelector("form")
    if (form) form.reset()
    this.speciesHiddenTargets.forEach(h => (h.value = ""))
    this.speciesPreviewTargets.forEach(p => (p.innerHTML = ""))
    if (this.hasFormStatusTarget) {
      this.formStatusTarget.textContent = ""
      this.formStatusTarget.className = "text-xs text-gray-500"
    }
  }

  // ── Species Search/Autocomplete (ported from sinnoh_map_controller) ──

  filterSpecies(event) {
    const input = event.target
    const query = input.value.toLowerCase().trim()
    const wrapper = input.closest("[data-timeline-target='speciesSearchWrapper']")
    const dropdown = wrapper.querySelector("[data-timeline-target='speciesDropdown']")

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
      dropdown.innerHTML = '<div class="px-3 py-2 text-xs text-gray-500">No species found</div>'
    } else {
      dropdown.innerHTML = matches
        .map(
          species => `
        <div class="px-3 py-1.5 text-sm text-gray-200 hover:bg-indigo-600 hover:text-white cursor-pointer transition"
             data-action="click->timeline#selectSpecies"
             data-species="${species}">
          ${species}
        </div>`
        )
        .join("")
    }

    dropdown.classList.remove("hidden")
  }

  selectSpecies(event) {
    event.stopPropagation()
    const species = event.currentTarget.dataset.species
    const wrapper = event.currentTarget.closest("[data-timeline-target='speciesSearchWrapper']")
    const input = wrapper.querySelector("input[type='text']")
    const hidden = wrapper.querySelector("[data-timeline-target='speciesHidden']")
    const dropdown = wrapper.querySelector("[data-timeline-target='speciesDropdown']")
    const preview = wrapper.querySelector("[data-timeline-target='speciesPreview']")

    input.value = species
    hidden.value = species
    dropdown.classList.add("hidden")

    if (preview) {
      preview.innerHTML = `<img src="/assets/sprites/${this.getSpriteFilename(species)}.png"
                                alt="${species}" width="28" height="28"
                                class="inline-block" loading="lazy"
                                onerror="this.style.display='none'">`
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

  // ── Form Submission (ported from sinnoh_map_controller) ──

  async submitCatch(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)

    if (this.hasFormStatusTarget) {
      this.formStatusTarget.textContent = "Saving..."
      this.formStatusTarget.className = "text-xs text-yellow-400"
    }

    // Save scroll position before reload
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
        if (this.hasFormStatusTarget) {
          this.formStatusTarget.textContent = "Saved!"
          this.formStatusTarget.className = "text-xs text-green-400"
        }
        setTimeout(() => window.location.reload(), 500)
      } else {
        const data = await response.json().catch(() => ({}))
        const msg = data.error || "Save failed"
        if (this.hasFormStatusTarget) {
          this.formStatusTarget.textContent = msg
          this.formStatusTarget.className = "text-xs text-red-400"
        }
      }
    } catch (error) {
      if (this.hasFormStatusTarget) {
        this.formStatusTarget.textContent = "Network error"
        this.formStatusTarget.className = "text-xs text-red-400"
      }
    }
  }

  // ── Gym Toggle (ported from sinnoh_map_controller) ──

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
        // Save scroll position before reload
        if (this.hasScrollContainerTarget) {
          sessionStorage.setItem("timeline-scroll", this.scrollContainerTarget.scrollLeft)
        }
        setTimeout(() => window.location.reload(), 300)
      }
    } catch (error) {
      console.error("Failed to toggle gym:", error)
    }
  }
}
