import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = [
    "poolList", "dropZone", "saveStatus", "poolCount", "poolEmpty",
    "tabButton", "tabPanel",
    "pokedexList", "pokedexSearch",
    "modal", "modalTitle", "modalStatus",
    "groupIdInput", "groupNicknameInput", "groupLocationSelect",
    "groupStatusSelect", "groupEulogyInput", "eulogyWrapper",
    "quickNavBar"
  ]
  static values = {
    assignUrl: String,
    assignFromPokedexUrl: String,
    unassignUrl: String,
    groupsUrl: String,
    reorderUrl: String,
    csrf: String,
    userId: String
  }

  connect() {
    // Track whether modal is in create or edit mode
    this.editingGroupId = null

    // Make the species pool sortable (draggable source)
    this.poolSortable = new Sortable(this.poolListTarget, {
      group: {
        name: "species",
        pull: "clone",
        put: false
      },
      sort: false,
      animation: 150,
      ghostClass: "opacity-30",
      filter: "[data-species-assignment-target='poolEmpty']"
    })

    // Make the pokédex list sortable (draggable source)
    if (this.hasPokedexListTarget) {
      this.pokedexSortable = new Sortable(this.pokedexListTarget, {
        group: {
          name: "species",
          pull: "clone",
          put: false
        },
        sort: false,
        animation: 150,
        ghostClass: "opacity-30"
      })
    }

    // Make the quick-nav pill bar reorderable
    if (this.hasQuickNavBarTarget) {
      this.navSortable = new Sortable(this.quickNavBarTarget, {
        animation: 200,
        ghostClass: "opacity-30",
        onEnd: () => this.reorderGroups()
      })
    }

    // Make each drop zone accept species cards
    this.dropZoneTargets.forEach(zone => {
      new Sortable(zone, {
        group: {
          name: "species",
          pull: false,
          put: "species"
        },
        animation: 150,
        onAdd: (evt) => this.onSpeciesDropped(evt, zone)
      })
    })
  }

  // ── Tab Switching ──

  switchTab(event) {
    const selectedTab = event.currentTarget.dataset.tab

    this.tabButtonTargets.forEach(btn => {
      const isActive = btn.dataset.tab === selectedTab
      btn.classList.toggle("text-indigo-300", isActive)
      btn.classList.toggle("border-indigo-500", isActive)
      btn.classList.toggle("text-gray-400", !isActive)
      btn.classList.toggle("border-transparent", !isActive)
      btn.setAttribute("aria-selected", isActive)
    })

    this.tabPanelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== selectedTab)
    })
  }

  // ── Pokédex Search ──

  filterPokedex() {
    const query = this.pokedexSearchTarget.value.toLowerCase().trim()
    const cards = this.pokedexListTarget.querySelectorAll(".pokedex-card")

    cards.forEach(card => {
      if (query === "") {
        card.classList.remove("hidden")
      } else {
        const name = card.dataset.speciesName.toLowerCase()
        card.classList.toggle("hidden", !name.includes(query))
      }
    })
  }

  // ── Group Modal ──

  openNewGroupModal() {
    this.editingGroupId = null
    this.modalTitleTarget.textContent = "New Group"
    this.groupIdInputTarget.value = ""
    this.groupNicknameInputTarget.value = ""
    this.groupLocationSelectTarget.value = ""
    this.groupStatusSelectTarget.value = "caught"
    this.groupEulogyInputTarget.value = ""
    this.eulogyWrapperTarget.classList.add("hidden")
    this.modalStatusTarget.textContent = ""
    this.modalTarget.classList.remove("hidden")
    this.groupNicknameInputTarget.focus()
  }

  openEditGroupModal(event) {
    const card = event.currentTarget.closest("[data-group-id]")
    if (!card) return

    this.editingGroupId = card.dataset.groupId
    this.modalTitleTarget.textContent = "Edit Group"
    this.groupIdInputTarget.value = card.dataset.groupId
    this.groupNicknameInputTarget.value = card.dataset.groupNickname || ""
    this.groupLocationSelectTarget.value = card.dataset.groupLocation || ""
    this.groupStatusSelectTarget.value = card.dataset.groupStatus || "caught"
    this.groupEulogyInputTarget.value = card.dataset.groupEulogy || ""
    this.toggleEulogy()
    this.modalStatusTarget.textContent = ""
    this.modalTarget.classList.remove("hidden")
    this.groupNicknameInputTarget.focus()
  }

  closeModal() {
    this.modalTarget.classList.add("hidden")
    this.editingGroupId = null
  }

  toggleEulogy() {
    const isDead = this.groupStatusSelectTarget.value === "dead"
    this.eulogyWrapperTarget.classList.toggle("hidden", !isDead)
  }

  async submitGroup(event) {
    event.preventDefault()

    const nickname = this.groupNicknameInputTarget.value.trim()
    const location = this.groupLocationSelectTarget.value
    const status = this.groupStatusSelectTarget.value
    const eulogy = this.groupEulogyInputTarget.value.trim()

    if (!nickname || !location) {
      this.modalStatusTarget.textContent = "Nickname and location are required"
      this.modalStatusTarget.className = "text-xs text-red-400"
      return
    }

    this.modalStatusTarget.textContent = "Saving..."
    this.modalStatusTarget.className = "text-xs text-yellow-400"

    try {
      let url, method
      const body = { nickname, location, status, eulogy }

      if (this.editingGroupId) {
        url = `${this.groupsUrlValue}/${this.editingGroupId}`
        method = "PATCH"
      } else {
        url = this.groupsUrlValue
        method = "POST"
      }

      const response = await fetch(url, {
        method,
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify(body)
      })

      if (response.ok) {
        // Reload page to get fresh DOM (Sortable instances need fresh elements)
        window.location.reload()
      } else {
        const data = await response.json()
        this.modalStatusTarget.textContent = data.error || "Save failed"
        this.modalStatusTarget.className = "text-xs text-red-400"
      }
    } catch (error) {
      this.modalStatusTarget.textContent = "Network error"
      this.modalStatusTarget.className = "text-xs text-red-400"
    }
  }

  async deleteGroup(event) {
    const card = event.currentTarget.closest("[data-group-id]")
    if (!card) return

    const groupId = card.dataset.groupId
    const nickname = card.dataset.groupNickname || "this group"

    if (!confirm(`Delete "${nickname}" and all its pokemon? This cannot be undone.`)) {
      return
    }

    try {
      const response = await fetch(`${this.groupsUrlValue}/${groupId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": this.csrfValue
        }
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Delete failed")
      }
    } catch (error) {
      alert("Network error — could not delete group")
    }
  }

  // ── Unassign Species ──

  async unassignSpecies(event) {
    const pokemonId = event.currentTarget.dataset.pokemonId
    if (!pokemonId) return

    try {
      const response = await fetch(this.unassignUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ pokemon_id: pokemonId })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        this.showStatus(data.error || "Unassign failed", "text-red-400")
      }
    } catch (error) {
      this.showStatus("Network error", "text-red-400")
    }
  }

  // ── Group Name Sidebar ──

  scrollToGroup(event) {
    const groupId = event.currentTarget.dataset.scrollToGroup
    if (!groupId) return

    const card = this.element.querySelector(`[data-group-id="${groupId}"]`)
    if (card) {
      card.scrollIntoView({ behavior: "smooth", block: "center" })
      // Brief highlight
      card.classList.add("ring-2", "ring-indigo-500")
      setTimeout(() => card.classList.remove("ring-2", "ring-indigo-500"), 1500)
    }
  }

  async reorderGroups() {
    if (!this.hasQuickNavBarTarget) return

    const pills = this.quickNavBarTarget.querySelectorAll("[data-scroll-to-group]")
    const groupIds = Array.from(pills).map(p => parseInt(p.dataset.scrollToGroup))

    try {
      const response = await fetch(this.reorderUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ group_ids: groupIds })
      })

      if (response.ok) {
        // Reorder the group cards in the DOM to match pill order
        const container = this.element.querySelector(".space-y-3")
        if (container) {
          groupIds.forEach(id => {
            const card = container.querySelector(`[data-group-id="${id}"]`)
            if (card) container.appendChild(card)
          })
        }
      }
    } catch (error) {
      // Silently fail — reload will fix ordering
    }
  }

  // ── Drag-and-Drop Assignment ──

  async onSpeciesDropped(evt, zone) {
    const card = evt.item
    const pokemonId = card.dataset.pokemonId
    const speciesName = card.dataset.speciesName
    const groupId = zone.dataset.groupId

    if ((!pokemonId && !speciesName) || !groupId) {
      this.bounceBack(card)
      return
    }

    this.showStatus("Saving...", "text-yellow-400")

    try {
      let url, body

      if (pokemonId) {
        // Existing flow: assign existing unassigned pool record
        url = this.assignUrlValue
        body = JSON.stringify({ pokemon_id: pokemonId, group_id: groupId })
      } else {
        // New flow: create + assign from pokédex
        url = this.assignFromPokedexUrlValue
        body = JSON.stringify({ species_name: speciesName, group_id: groupId })
      }

      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: body
      })

      if (response.ok) {
        // Success — lock the species in place
        this.lockSpecies(card, zone)

        // Remove from pool only if it was a pool card
        if (pokemonId) {
          const original = this.poolListTarget.querySelector(`[data-pokemon-id="${pokemonId}"]`)
          if (original) original.remove()
          this.updatePoolCount()
        }
        // Pokédex cards stay in the list (clone behavior)

        this.showStatus("Assigned!", "text-green-400")
        setTimeout(() => this.showStatus("", ""), 2000)
      } else {
        const data = await response.json()
        this.showStatus(data.error || "Assignment failed", "text-red-400")
        this.bounceBack(card)
      }
    } catch (error) {
      this.showStatus("Network error", "text-red-400")
      this.bounceBack(card)
    }
  }

  lockSpecies(card, zone) {
    const speciesName = card.querySelector("span")?.textContent?.trim() || "?"

    // Replace the drop zone with a locked badge
    zone.outerHTML = `
      <span class="inline-flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg bg-indigo-900/60 text-indigo-200 border border-indigo-700">
        ${speciesName}
        <svg class="w-3 h-3 opacity-50" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"/>
        </svg>
      </span>
    `

    // Update the group card's status
    const groupCard = zone?.closest("[data-group-id]")
    if (groupCard) {
      const remaining = groupCard.querySelectorAll(".drop-zone").length
      const statusEl = groupCard.querySelector("span.text-yellow-400, span.text-green-400")
      if (statusEl && remaining === 0) {
        statusEl.textContent = "Complete"
        statusEl.className = "text-xs text-green-400"
      } else if (statusEl) {
        statusEl.textContent = `${remaining} missing`
      }
    }
  }

  bounceBack(card) {
    card.remove()
  }

  updatePoolCount() {
    const remaining = this.poolListTarget.querySelectorAll(".species-card").length
    if (this.hasPoolCountTarget) {
      this.poolCountTarget.textContent = `(${remaining} remaining)`
    }
    if (this.hasPoolEmptyTarget) {
      this.poolEmptyTarget.classList.toggle("hidden", remaining > 0)
    }
  }

  showStatus(text, className) {
    if (this.hasSaveStatusTarget) {
      this.saveStatusTarget.textContent = text
      this.saveStatusTarget.className = `text-xs ${className}`
    }
  }
}
