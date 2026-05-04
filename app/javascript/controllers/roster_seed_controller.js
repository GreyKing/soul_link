// Click-to-copy for the run-roster card's seed line (Step 21 R3).
// On click, write the seed to clipboard and briefly swap the element's
// text to "Copied!" before reverting after 1s. The CSS hover hint
// ("click to copy") is owned by `.roster-card .seed:hover::after` —
// this controller only handles the actual copy.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async copy(event) {
    event.preventDefault()
    const original = this.element.textContent
    // The element renders "Seed: <seed>" — strip the prefix when we
    // copy so users get just the hex blob in their clipboard.
    const seed = original.replace(/^Seed:\s*/, "")
    try {
      await navigator.clipboard.writeText(seed)
      this.element.textContent = "Copied!"
      setTimeout(() => { this.element.textContent = original }, 1000)
    } catch (e) {
      console.error("RosterSeed: copy failed:", e)
      window.alert("Could not copy seed — copy it manually.")
    }
  }
}
