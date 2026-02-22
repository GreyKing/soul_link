import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["poolList", "dropZone", "saveStatus", "poolCount", "poolEmpty"]
  static values = { assignUrl: String, csrf: String, userId: Number }

  connect() {
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

  async onSpeciesDropped(evt, zone) {
    const card = evt.item
    const pokemonId = card.dataset.pokemonId
    const groupId = zone.dataset.groupId

    if (!pokemonId || !groupId) {
      this.bounceBack(card)
      return
    }

    this.showStatus("Saving...", "text-yellow-400")

    try {
      const response = await fetch(this.assignUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ pokemon_id: pokemonId, group_id: groupId })
      })

      if (response.ok) {
        // Success — lock the species in place
        this.lockSpecies(card, zone)

        // Remove the original from the pool (since we used clone)
        const original = this.poolListTarget.querySelector(`[data-pokemon-id="${pokemonId}"]`)
        if (original) original.remove()

        this.updatePoolCount()
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
