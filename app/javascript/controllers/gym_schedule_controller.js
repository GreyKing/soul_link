import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "statusBadge", "statusInfo",
    "rsvpGrid", "rsvpActions", "cancelAction"
  ]
  static values = {
    scheduleId: Number,
    userId: String,
    players: Array
  }

  connect() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "GymScheduleChannel", schedule_id: this.scheduleIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
    this.state = null
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  handleMessage(data) {
    if (data.error) {
      console.error("Schedule error:", data.error)
      return
    }
    if (data.type === "state_update") {
      this.state = data.state
      this.render()
    }
  }

  // ── User Actions ──

  rsvpYes() {
    this.subscription.perform("rsvp", { response: "yes" })
  }

  rsvpMaybe() {
    this.subscription.perform("rsvp", { response: "maybe" })
  }

  rsvpNo() {
    this.subscription.perform("rsvp", { response: "no" })
  }

  cancel() {
    if (confirm("Cancel this schedule?")) {
      this.subscription.perform("cancel")
    }
  }

  // ── Rendering ──

  render() {
    if (!this.state) return

    this.renderStatus()
    this.renderRsvpGrid()
    this.renderActions()
  }

  renderStatus() {
    const { status } = this.state
    const badge = this.statusBadgeTarget

    badge.textContent = this.statusDisplayName(status)

    // Reset classes then apply status-specific styling
    badge.className = "px-3 py-1 rounded-full text-sm font-medium"
    switch (status) {
      case "confirmed":
        badge.classList.add("bg-green-900/50", "text-green-300", "border", "border-green-700")
        break
      case "cancelled":
        badge.classList.add("bg-red-900/50", "text-red-300", "border", "border-red-700")
        break
      case "completed":
        badge.classList.add("bg-blue-900/50", "text-blue-300", "border", "border-blue-700")
        break
      default: // proposed
        badge.classList.add("bg-yellow-900/50", "text-yellow-300", "border", "border-yellow-700")
    }

    const counts = []
    if (this.state.yes_count > 0) counts.push(`${this.state.yes_count} yes`)
    if (this.state.maybe_count > 0) counts.push(`${this.state.maybe_count} maybe`)
    if (this.state.no_count > 0) counts.push(`${this.state.no_count} no`)
    this.statusInfoTarget.textContent = counts.length > 0
      ? `Proposed by ${this.state.proposer_name} — ${counts.join(", ")}`
      : `Proposed by ${this.state.proposer_name}`
  }

  renderRsvpGrid() {
    const rsvps = this.state.rsvps || {}
    const cards = this.rsvpGridTarget.querySelectorAll("[data-player-id]")

    cards.forEach(card => {
      const pid = card.dataset.playerId
      const response = rsvps[pid]
      const statusEl = card.querySelector(".rsvp-status")

      if (statusEl) {
        if (response === "yes") {
          statusEl.textContent = "Yes"
          statusEl.className = "text-xs mt-2 rsvp-status text-green-400"
        } else if (response === "maybe") {
          statusEl.textContent = "Maybe"
          statusEl.className = "text-xs mt-2 rsvp-status text-yellow-400"
        } else if (response === "no") {
          statusEl.textContent = "No"
          statusEl.className = "text-xs mt-2 rsvp-status text-red-400"
        } else {
          statusEl.textContent = "Pending"
          statusEl.className = "text-xs mt-2 rsvp-status text-gray-500"
        }
      }

      // Border color based on response
      card.classList.remove("border-green-600", "border-yellow-600", "border-red-600", "border-gray-700")
      if (response === "yes") {
        card.classList.add("border-green-600")
      } else if (response === "maybe") {
        card.classList.add("border-yellow-600")
      } else if (response === "no") {
        card.classList.add("border-red-600")
      } else {
        card.classList.add("border-gray-700")
      }
    })
  }

  renderActions() {
    const { status, rsvps } = this.state
    const isActive = status === "proposed" || status === "confirmed"
    const myRsvp = rsvps ? rsvps[this.userIdValue] : null

    // Show/hide RSVP buttons
    if (isActive) {
      this.rsvpActionsTarget.classList.remove("hidden")
      // Disable buttons and highlight current response
      const buttons = this.rsvpActionsTarget.querySelectorAll("button")
      buttons.forEach(btn => {
        btn.disabled = false
        btn.classList.remove("ring-2", "ring-white", "opacity-50")
      })
      if (myRsvp) {
        buttons.forEach(btn => {
          const btnResponse = btn.dataset.action.includes("Yes") ? "yes"
            : btn.dataset.action.includes("Maybe") ? "maybe" : "no"
          if (btnResponse === myRsvp) {
            btn.classList.add("ring-2", "ring-white")
          } else {
            btn.classList.add("opacity-50")
          }
        })
      }
    } else {
      this.rsvpActionsTarget.classList.add("hidden")
    }

    // Show/hide cancel button
    if (isActive) {
      this.cancelActionTarget.classList.remove("hidden")
    } else {
      this.cancelActionTarget.classList.add("hidden")
    }
  }

  // ── Helpers ──

  statusDisplayName(status) {
    const names = {
      proposed: "Proposed",
      confirmed: "Confirmed",
      completed: "Completed",
      cancelled: "Cancelled"
    }
    return names[status] || status
  }
}
