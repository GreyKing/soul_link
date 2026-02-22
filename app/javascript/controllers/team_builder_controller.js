import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static targets = ["teamList", "poolList", "saveStatus", "teamCount", "teamEmpty", "poolEmpty"]
  static values = { updateUrl: String, csrf: String, userId: Number }

  connect() {
    this.maxSlots = 6

    this.teamSortable = new Sortable(this.teamListTarget, {
      group: "pokemon",
      animation: 150,
      ghostClass: "opacity-30",
      dragClass: "shadow-lg",
      onAdd: () => this.onTeamChanged(),
      onSort: () => this.onTeamChanged(),
      onRemove: () => this.onTeamChanged()
    })

    this.poolSortable = new Sortable(this.poolListTarget, {
      group: "pokemon",
      animation: 150,
      ghostClass: "opacity-30",
      dragClass: "shadow-lg",
      onAdd: () => {
        this.updateEmptyStates()
        this.updatePositions()
      }
    })

    // Show initial positions
    this.updatePositions()
  }

  onTeamChanged() {
    // Enforce max 6 — bounce extras back to pool
    const cards = this.teamListTarget.querySelectorAll(".pokemon-card")
    if (cards.length > this.maxSlots) {
      for (let i = this.maxSlots; i < cards.length; i++) {
        this.poolListTarget.prepend(cards[i])
      }
    }

    this.updateEmptyStates()
    this.updatePositions()
    this.save()
  }

  updateEmptyStates() {
    const teamCards = this.teamListTarget.querySelectorAll(".pokemon-card").length
    const poolCards = this.poolListTarget.querySelectorAll(".pokemon-card").length

    // Update team count
    if (this.hasTeamCountTarget) {
      this.teamCountTarget.textContent = `(${teamCards}/${this.maxSlots})`
    }

    // Show/hide empty messages
    if (this.hasTeamEmptyTarget) {
      this.teamEmptyTarget.style.display = teamCards === 0 ? "" : "none"
    }
    if (this.hasPoolEmptyTarget) {
      this.poolEmptyTarget.style.display = poolCards === 0 ? "" : "none"
    }
  }

  async save() {
    const cards = this.teamListTarget.querySelectorAll(".pokemon-card")
    const groupIds = Array.from(cards).map(c => c.dataset.groupId)

    this.showStatus("Saving...", "text-yellow-400")

    try {
      const response = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ group_ids: groupIds })
      })

      if (response.ok) {
        this.showStatus("Saved!", "text-green-400")
        setTimeout(() => this.showStatus("", ""), 2000)
      } else {
        const data = await response.json()
        this.showStatus(data.error || "Save failed", "text-red-400")
      }
    } catch (error) {
      this.showStatus("Network error", "text-red-400")
    }
  }

  updatePositions() {
    // Show position numbers on team cards, hide on pool cards
    const teamCards = this.teamListTarget.querySelectorAll(".pokemon-card")
    teamCards.forEach((card, idx) => {
      const badge = card.querySelector(".position-badge")
      if (badge) {
        badge.textContent = `#${idx + 1}`
        badge.classList.remove("hidden")
      }
    })

    const poolCards = this.poolListTarget.querySelectorAll(".pokemon-card")
    poolCards.forEach(card => {
      const badge = card.querySelector(".position-badge")
      if (badge) {
        badge.textContent = ""
        badge.classList.add("hidden")
      }
    })
  }

  showStatus(text, className) {
    if (this.hasSaveStatusTarget) {
      this.saveStatusTarget.textContent = text
      this.saveStatusTarget.className = `text-xs ${className}`
    }
  }
}
