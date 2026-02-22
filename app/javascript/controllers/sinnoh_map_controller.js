import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "svg", "location", "popover", "modal",
    "modalLocationName", "modalLocationKey", "nicknameInput",
    "speciesSearchWrapper", "speciesHidden", "speciesDropdown", "speciesPreview",
    "modalStatus"
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
    // Bind handlers so we can remove them properly
    this._handleDocumentClick = this.handleDocumentClick.bind(this)
    this._closeAllDropdowns = this.closeAllDropdowns.bind(this)
    document.addEventListener("click", this._handleDocumentClick)
    document.addEventListener("click", this._closeAllDropdowns)
  }

  disconnect() {
    document.removeEventListener("click", this._handleDocumentClick)
    document.removeEventListener("click", this._closeAllDropdowns)
  }

  // ── Location Click Handler ──

  onLocationClick(event) {
    event.stopPropagation()
    const node = event.currentTarget
    const key = node.dataset.locationKey
    const status = node.dataset.status
    const name = node.dataset.locationName

    if (status === "uncaught") {
      this.openModal(key, name)
    } else {
      this.showPopover(node, key, name, status)
    }
  }

  onSpecialClick(event) {
    event.stopPropagation()
    const btn = event.currentTarget
    const key = btn.dataset.locationKey
    const status = btn.dataset.status
    const name = btn.dataset.locationName

    if (status === "uncaught") {
      this.openModal(key, name)
    } else {
      this.showSpecialPopover(btn, key, name, status)
    }
  }

  showSpecialPopover(btn, key, name, status) {
    const popover = this.popoverTarget

    // Parse groups from data attribute
    let groups = []
    try { groups = JSON.parse(btn.dataset.groups || "[]") } catch (_) {}

    // Build same popover HTML as SVG locations
    let html = `
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-bold text-white">${name}</h3>
        <button data-action="click->sinnoh-map#hidePopover" class="text-gray-400 hover:text-white text-lg leading-none">&times;</button>
      </div>
    `

    groups.forEach(group => {
      const isDead = group.status === "dead"
      html += `
        <div class="mb-3 pb-3 border-b border-gray-700 last:border-0">
          <div class="flex items-center justify-between mb-1.5">
            <span class="text-sm font-semibold ${isDead ? 'text-red-300' : 'text-white'}">${group.nickname}</span>
            <span class="text-xs ${isDead ? 'text-red-400' : 'text-green-400'} font-medium">${isDead ? '💀 Dead' : '✓ Caught'}</span>
          </div>
          <div class="flex flex-wrap gap-1.5">
      `
      if (group.pokemon) {
        group.pokemon.forEach(p => {
          const sprite = p.sprite ? `<img src="/assets/sprites/${p.sprite}.png" alt="${p.species}" width="20" height="20" class="inline-block" onerror="this.style.display='none'">` : ''
          html += `<span class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-gray-700/50 text-gray-300">${sprite}<span class="font-medium">${p.player}</span> <span class="text-gray-500">${p.species}</span></span>`
        })
      }
      html += '</div></div>'
    })

    html += `
      <button data-action="click->sinnoh-map#addCatchAtLocation" data-location-key="${key}" data-location-name="${name}"
              class="mt-2 w-full text-xs px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition font-medium">
        + Add Another Catch
      </button>
    `

    popover.innerHTML = html

    // Position near the button
    const btnRect = btn.getBoundingClientRect()
    const containerRect = this.element.getBoundingClientRect()
    popover.style.left = `${btnRect.left - containerRect.left}px`
    popover.style.top = `${btnRect.top - containerRect.top - 10}px`

    popover.classList.remove("hidden")

    // Adjust if off screen
    requestAnimationFrame(() => {
      const popRect = popover.getBoundingClientRect()
      if (popRect.bottom > window.innerHeight - 10) {
        popover.style.top = `${btnRect.top - containerRect.top - popRect.height - 10}px`
      }
    })
  }

  // ── Popover for Caught/Dead Locations ──

  showPopover(node, key, name, status) {
    const popover = this.popoverTarget

    // Parse embedded group data
    let groups = []
    try {
      groups = JSON.parse(node.dataset.groups || "[]")
    } catch (e) {
      // Also check if it's an HTML element (special encounters outside SVG)
      const el = this.element.querySelector(`[data-location-key="${key}"][data-groups]`)
      if (el) {
        try { groups = JSON.parse(el.dataset.groups || "[]") } catch (_) {}
      }
    }

    let html = `
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-bold text-white">${name}</h3>
        <button data-action="click->sinnoh-map#hidePopover" class="text-gray-400 hover:text-white text-lg leading-none">&times;</button>
      </div>
    `

    if (groups.length > 0) {
      groups.forEach(group => {
        const isDead = group.status === "dead"
        const statusBadge = isDead
          ? '<span class="text-xs text-red-400 font-medium">💀 Dead</span>'
          : '<span class="text-xs text-green-400 font-medium">✓ Caught</span>'

        html += `
          <div class="mb-3 pb-3 border-b border-gray-700 last:border-0 last:mb-0 last:pb-0">
            <div class="flex items-center justify-between mb-1.5">
              <span class="text-sm font-semibold ${isDead ? 'text-red-300' : 'text-white'}">${group.nickname}</span>
              ${statusBadge}
            </div>
            ${group.caught_at ? `<div class="text-[10px] text-gray-500 mb-1.5">Caught: ${group.caught_at}</div>` : ''}
            ${group.eulogy ? `<div class="text-[10px] text-gray-400 italic mb-1.5">"${group.eulogy}"</div>` : ''}
            <div class="flex flex-wrap gap-1.5">
        `

        if (group.pokemon && group.pokemon.length > 0) {
          group.pokemon.forEach(p => {
            const spriteHtml = p.sprite
              ? `<img src="/assets/sprites/${p.sprite}.png" alt="${p.species}" width="20" height="20" class="inline-block" loading="lazy" onerror="this.style.display='none'">`
              : ''
            html += `
              <span class="inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full bg-gray-700/50 text-gray-300">
                ${spriteHtml}
                <span class="font-medium">${p.player}</span>
                <span class="text-gray-500">${p.species}</span>
              </span>
            `
          })
        } else {
          html += '<span class="text-xs text-gray-500">No species assigned yet</span>'
        }

        html += `
            </div>
          </div>
        `
      })
    }

    // Add catch button
    html += `
      <button data-action="click->sinnoh-map#addCatchAtLocation"
              data-location-key="${key}" data-location-name="${name}"
              class="mt-2 w-full text-xs px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white rounded-lg transition font-medium">
        + Add ${groups.length > 0 ? 'Another' : 'New'} Catch
      </button>
    `

    popover.innerHTML = html

    // Position popover near the clicked element
    this.positionPopover(node, popover)
    popover.classList.remove("hidden")
  }

  positionPopover(node, popover) {
    const svgTarget = this.svgTarget
    const svgRect = svgTarget.getBoundingClientRect()
    const containerRect = this.element.getBoundingClientRect()

    // Get the click target's position in SVG coordinates
    let cx, cy
    if (node.tagName === "g") {
      // Location node group — skip the invisible hit area (first transparent circle)
      // and find the actual visible shape
      const shapes = node.querySelectorAll("rect, circle, ellipse")
      for (const shape of shapes) {
        if (shape.getAttribute("fill") === "transparent") continue
        const bbox = shape.getBBox()
        cx = bbox.x + bbox.width / 2
        cy = bbox.y + bbox.height / 2
        break
      }
    }

    if (cx !== undefined) {
      // Convert SVG coords to screen coords
      const viewBox = svgTarget.viewBox.baseVal
      const scaleX = svgRect.width / viewBox.width
      const scaleY = svgRect.height / viewBox.height
      const scale = Math.min(scaleX, scaleY)

      const offsetX = (svgRect.width - viewBox.width * scale) / 2
      const offsetY = (svgRect.height - viewBox.height * scale) / 2

      const screenX = svgRect.left - containerRect.left + offsetX + cx * scale
      const screenY = svgRect.top - containerRect.top + offsetY + cy * scale

      popover.style.left = `${screenX + 20}px`
      popover.style.top = `${screenY - 20}px`

      // Keep popover within container bounds
      requestAnimationFrame(() => {
        const popRect = popover.getBoundingClientRect()
        if (popRect.right > containerRect.right - 10) {
          popover.style.left = `${screenX - popRect.width - 20}px`
        }
        if (popRect.bottom > containerRect.bottom - 10) {
          popover.style.top = `${screenY - popRect.height + 20}px`
        }
      })
    }
  }

  hidePopover() {
    this.popoverTarget.classList.add("hidden")
  }

  handleDocumentClick(event) {
    if (!this.popoverTarget.contains(event.target) &&
        !event.target.closest("[data-sinnoh-map-target='location']") &&
        !event.target.closest("[data-action*='onLocationClick']")) {
      this.hidePopover()
    }
  }

  addCatchAtLocation(event) {
    const key = event.currentTarget.dataset.locationKey
    const name = event.currentTarget.dataset.locationName
    this.hidePopover()
    this.openModal(key, name)
  }

  // ── Catch Modal ──

  openModal(locationKey, locationName) {
    this.modalLocationNameTarget.textContent = locationName
    this.modalLocationKeyTarget.value = locationKey
    this.modalTarget.classList.remove("hidden")
    // Focus nickname input after a tick (animation)
    requestAnimationFrame(() => {
      this.nicknameInputTarget.focus()
    })
  }

  closeModal() {
    this.modalTarget.classList.add("hidden")
    // Reset form
    const form = this.modalTarget.querySelector("form")
    if (form) form.reset()
    this.speciesHiddenTargets.forEach(h => h.value = "")
    this.speciesPreviewTargets.forEach(p => p.innerHTML = "")
    if (this.hasModalStatusTarget) {
      this.modalStatusTarget.textContent = ""
    }
  }

  onModalBackdropClick(event) {
    if (event.target === this.modalTarget) {
      this.closeModal()
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  // ── Species Search/Autocomplete ──

  filterSpecies(event) {
    const input = event.target
    const query = input.value.toLowerCase().trim()
    const wrapper = input.closest("[data-sinnoh-map-target='speciesSearchWrapper']")
    const dropdown = wrapper.querySelector("[data-sinnoh-map-target='speciesDropdown']")

    if (query.length < 1) {
      dropdown.classList.add("hidden")
      return
    }

    // Filter species list — prioritize starts-with, then includes
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
      dropdown.innerHTML = matches.map(species =>
        `<div class="px-3 py-1.5 text-sm text-gray-200 hover:bg-indigo-600 hover:text-white cursor-pointer transition"
              data-action="click->sinnoh-map#selectSpecies"
              data-species="${species}">
          ${species}
        </div>`
      ).join("")
    }

    dropdown.classList.remove("hidden")
  }

  selectSpecies(event) {
    event.stopPropagation()
    const species = event.currentTarget.dataset.species
    const wrapper = event.currentTarget.closest("[data-sinnoh-map-target='speciesSearchWrapper']")
    const input = wrapper.querySelector("input[type='text']")
    const hidden = wrapper.querySelector("[data-sinnoh-map-target='speciesHidden']")
    const dropdown = wrapper.querySelector("[data-sinnoh-map-target='speciesDropdown']")
    const preview = wrapper.querySelector("[data-sinnoh-map-target='speciesPreview']")

    input.value = species
    hidden.value = species
    dropdown.classList.add("hidden")

    // Show sprite preview
    if (preview) {
      // Use the pokedex data to build a sprite URL
      // We'll create a simple img tag — the helper is server-side so we construct it manually
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
    if (!event.target.closest("[data-sinnoh-map-target='speciesSearchWrapper']")) {
      this.speciesDropdownTargets.forEach(d => d.classList.add("hidden"))
    }
  }

  // ── Form Submission ──

  async submitCatch(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)

    if (this.hasModalStatusTarget) {
      this.modalStatusTarget.textContent = "Saving..."
      this.modalStatusTarget.className = "text-xs text-yellow-400"
    }

    try {
      const response = await fetch(this.createGroupUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfValue,
          "Accept": "application/json"
        },
        body: formData
      })

      if (response.ok) {
        const data = await response.json()
        if (this.hasModalStatusTarget) {
          this.modalStatusTarget.textContent = "Saved!"
          this.modalStatusTarget.className = "text-xs text-green-400"
        }
        // Reload the page to show updated map
        setTimeout(() => {
          window.location.reload()
        }, 500)
      } else {
        const data = await response.json().catch(() => ({}))
        const msg = data.error || "Save failed"
        if (this.hasModalStatusTarget) {
          this.modalStatusTarget.textContent = msg
          this.modalStatusTarget.className = "text-xs text-red-400"
        }
      }
    } catch (error) {
      if (this.hasModalStatusTarget) {
        this.modalStatusTarget.textContent = "Network error"
        this.modalStatusTarget.className = "text-xs text-red-400"
      }
    }
  }

  // ── Gym Toggle ──

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
        this.updateGymBadges()
        // Reload to update level cap info and map badges
        setTimeout(() => window.location.reload(), 300)
      }
    } catch (error) {
      console.error("Failed to toggle gym:", error)
    }
  }

  updateGymBadges() {
    // Update header gym badge buttons
    this.element.querySelectorAll("[data-gym-number]").forEach(btn => {
      const num = parseInt(btn.dataset.gymNumber)
      const beaten = this.gymsDefeatedValue >= num
      if (btn.tagName === "BUTTON") {
        // Header buttons
        btn.className = `w-7 h-7 rounded-full border-2 flex items-center justify-center text-[10px] font-bold transition ${
          beaten ? 'bg-yellow-500 border-yellow-400 text-gray-900' : 'bg-gray-700 border-gray-600 text-gray-400 hover:border-gray-500'
        }`
      }
    })

    // Update SVG gym badges
    this.element.querySelectorAll("[data-gym-badge]").forEach(circle => {
      const num = parseInt(circle.dataset.gymBadge)
      const beaten = this.gymsDefeatedValue >= num
      circle.setAttribute("fill", beaten ? "#eab308" : "#1f2937")
      circle.setAttribute("stroke", beaten ? "#facc15" : "#6b7280")
      // Update the text sibling
      const text = circle.nextElementSibling
      if (text && text.tagName === "text") {
        text.setAttribute("fill", beaten ? "#1f2937" : "#9ca3af")
      }
    })
  }
}
