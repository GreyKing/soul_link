// Run-roster YOU-badge marker. Runs alongside the run sidebar on the
// emulator page. After Step 9 (KG-1) wrapped each session card in a
// turbo_frame_tag for real-time broadcast replacement, the YOU badge +
// 4px-border that used to mark the current player's card got dropped
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
        card.classList.add("gb-card--current-user")
        // Lazy-add the YOU badge once per card. The card's rendered
        // markup doesn't include the badge (the partial has no
        // current_user context); we inject it here.
        if (!card.querySelector("[data-roster-you-marker-badge]")) {
          const badge = document.createElement("span")
          badge.dataset.rosterYouMarkerBadge = "true"
          badge.className = "type-text"
          badge.textContent = "YOU"
          badge.style.cssText = "border-color: var(--d1); background: var(--d1); color: var(--l2); font-size: 9px; margin-left: 6px;"
          // Append to the player_label row (first child div with the
          // player name). The roster card's first nested div carries
          // the player_label flex layout.
          const labelRow = card.querySelector("div")
          if (labelRow) labelRow.appendChild(badge)
        }
      } else {
        card.classList.remove("gb-card--current-user")
        const badge = card.querySelector("[data-roster-you-marker-badge]")
        if (badge) badge.remove()
      }
    })
  }
}
