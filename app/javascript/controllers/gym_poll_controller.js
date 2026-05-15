import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets   = ["slotList", "slotCard", "voteButton", "resetButton", "bannerLocked", "bannerAllPast"]
  static values    = { id: Number, state: Object, userId: String }

  connect() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "GymPollChannel", id: this.idValue },
      {
        received: (data) => this.handleMessage(data),
        connected: () => console.log("GymPollChannel connected"),
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  vote(event) {
    const slotIndex = parseInt(event.currentTarget.dataset.slotIndex, 10)
    const response  = event.currentTarget.dataset.response
    this.subscription.perform("vote", { slot_index: slotIndex, response })
  }

  reset() {
    if (!confirm("Reset the current poll?")) return
    this.subscription.perform("reset")
  }

  handleMessage(data) {
    if (data.type === "state_update") {
      this.stateValue = data.state
      this.render()
    } else if (data.type === "poll_reset") {
      window.location.reload()
    } else if (data.type === "error") {
      alert(data.message)
    }
  }

  render() {
    const state = this.stateValue
    if (state.status === "locked") {
      this.bannerLockedTarget?.classList.remove("hidden")
      this.voteButtonTargets.forEach((b) => (b.disabled = true))
    }
    state.slots.forEach((slot) => {
      const card = this.slotCardTargets.find((c) => parseInt(c.dataset.slotIndex, 10) === slot.index)
      if (!card) return
      card.querySelector(".tally").textContent =
        `${slot.yes_count} yes / ${slot.maybe_count} maybe / ${slot.no_count} no / ${slot.pending_count} pending`
      if (slot.past) card.classList.add("past")
      if (state.locked_slot_index === slot.index) card.classList.add("locked-winner")
    })
    state.players.forEach((player) => {
      const uid = player.discord_user_id
      state.slots.forEach((slot) => {
        const card = this.slotCardTargets.find((c) => parseInt(c.dataset.slotIndex, 10) === slot.index)
        if (!card) return
        const chip = Array.from(card.querySelectorAll(".chip")).find((c) => c.textContent.trim() === player.display_name)
        if (!chip) return
        const response = state.votes[uid]?.[String(slot.index)] || "pending"
        chip.className = `chip chip-${response}`
      })
    })
  }
}
