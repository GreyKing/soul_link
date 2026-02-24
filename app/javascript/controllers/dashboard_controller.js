import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "catchModal", "catchNickname", "catchLocation", "catchSpecies", "catchStatus"
  ]
  static values = {
    groupsUrl: String,
    csrf: String,
    userId: Number
  }

  // ── Quick-Catch Modal ──

  openCatchModal() {
    this.catchNicknameTarget.value = ""
    this.catchLocationTarget.value = ""
    this.catchSpeciesTarget.value = ""
    this.catchStatusTarget.textContent = ""
    this.catchModalTarget.classList.remove("hidden")
    this.catchNicknameTarget.focus()
  }

  closeCatchModal() {
    this.catchModalTarget.classList.add("hidden")
  }

  async submitCatch(event) {
    event.preventDefault()

    const nickname = this.catchNicknameTarget.value.trim()
    const location = this.catchLocationTarget.value
    const species = this.catchSpeciesTarget.value.trim()

    if (!nickname || !location || !species) {
      this.catchStatusTarget.textContent = "All fields are required"
      this.catchStatusTarget.className = "text-xs text-red-400"
      return
    }

    this.catchStatusTarget.textContent = "Saving..."
    this.catchStatusTarget.className = "text-xs text-yellow-400"

    try {
      // Build species payload keyed by current user's discord ID
      const speciesPayload = {}
      speciesPayload[this.userIdValue] = species

      const response = await fetch(this.groupsUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({
          nickname: nickname,
          location: location,
          species: speciesPayload
        })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        this.catchStatusTarget.textContent = data.error || "Save failed"
        this.catchStatusTarget.className = "text-xs text-red-400"
      }
    } catch (error) {
      this.catchStatusTarget.textContent = "Network error"
      this.catchStatusTarget.className = "text-xs text-red-400"
    }
  }

  // ── Mark Dead ──

  async markDead(event) {
    const groupId = event.currentTarget.dataset.groupId
    const nickname = event.currentTarget.dataset.groupNickname || "this group"

    if (!confirm(`Mark "${nickname}" as dead? This will kill all linked pokemon and remove from teams.`)) {
      return
    }

    try {
      const response = await fetch(`${this.groupsUrlValue}/${groupId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfValue
        },
        body: JSON.stringify({ status: "dead" })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.error || "Failed to mark as dead")
      }
    } catch (error) {
      alert("Network error")
    }
  }
}
