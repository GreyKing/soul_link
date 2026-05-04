// Run-roster YOU-badge marker. Runs alongside the run sidebar on the
// emulator page. After Step 9 (KG-1) wrapped each session card in a
// turbo_frame_tag for real-time broadcast replacement, the YOU badge +
// amber-border that used to mark the current player's card got dropped
// from the partial — preserving them across stream replacements would
// have required passing current_user_id into a model callback (a layer
// violation) or rendering markers outside the frame in DOM-fragile ways.
//
// This controller solves it cleanly client-side: it reads
// `currentUserId` from a Stimulus value (set in the layout where the
// controller context exists), then walks each `[data-discord-user-id]`
// inside its element and decorates the matching card. Re-runs after
// each `turbo:before-stream-render` so the marker re-applies after a
// broadcast replaces a frame's contents.
//
// Step 21 R3: the roster card class is now `.roster-card`. The "you"
// state lands on the wrapper as a plain `you` class (CSS `.roster-card.you`
// owns the amber border). The badge gets injected into the
// `.roster-card-name` span — that's where the new layout positions it,
// inline with the player name.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { currentUserId: String }

  connect() {
    this._onTurboStreamRender = () => {
      // Defer one tick so the new contents are in the DOM before we
      // walk them — turbo:before-stream-render fires BEFORE the swap.
      requestAnimationFrame(() => this.apply())
    }
    document.addEventListener("turbo:before-stream-render", this._onTurboStreamRender)
    this.apply()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this._onTurboStreamRender)
  }

  apply() {
    if (!this.currentUserIdValue) return
    const cards = this.element.querySelectorAll("[data-discord-user-id]")
    cards.forEach((card) => {
      const isMe = card.dataset.discordUserId === this.currentUserIdValue
      if (isMe) {
        card.classList.add("you")
        // Lazy-add the YOU badge once per card. The card's rendered
        // markup doesn't include the badge (the partial has no
        // current_user context); we inject it into the name span here.
        if (!card.querySelector("[data-roster-you-marker-badge]")) {
          const badge = document.createElement("span")
          badge.dataset.rosterYouMarkerBadge = "true"
          badge.className = "you-badge"
          badge.textContent = "YOU"
          const nameEl = card.querySelector(".roster-card-name")
          if (nameEl) nameEl.appendChild(badge)
        }
      } else {
        card.classList.remove("you")
        const badge = card.querySelector("[data-roster-you-marker-badge]")
        if (badge) badge.remove()
      }
    })
  }
}
