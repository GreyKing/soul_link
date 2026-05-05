import { Controller } from "@hotwired/stimulus"

// Step 22 R2 — pre-fill the dashboard catch modal from a review-tray row
// + dismiss handling. The action chain on LOG/EDIT buttons is:
//   click->dashboard#openCatchModal click->review-tray#prefillCatch
// openCatchModal blanks the three fields and focuses nickname; this
// controller then writes species + location into the modal targets.
// Order matters — reversing it would have openCatchModal wipe the
// pre-filled values.
//
// SKIP fades the row to opacity 0.4 (`.dismissed` class) and decrements
// the count pill. Does not persist; reload resurfaces the row. KG-35.
export default class extends Controller {
  static targets = [ "row", "count" ]

  prefillCatch(event) {
    const params = event.params || {}
    const species = params.species || event.currentTarget?.dataset?.reviewTrayPrefillSpeciesParam || ""
    const location = params.location || event.currentTarget?.dataset?.reviewTrayPrefillLocationParam || ""

    const speciesEl = document.querySelector('[data-dashboard-target="catchSpecies"]')
    const locationEl = document.querySelector('[data-dashboard-target="catchLocation"]')

    if (speciesEl) speciesEl.value = species
    if (locationEl) locationEl.value = location
  }

  dismiss(event) {
    const row = event.currentTarget.closest('[data-review-tray-target="row"]')
    if (!row || row.classList.contains("dismissed")) return
    row.classList.add("dismissed")

    if (this.hasCountTarget) {
      const remaining = this.rowTargets.filter((r) => !r.classList.contains("dismissed")).length
      this.countTarget.textContent = `${remaining} NEW`
    }
  }
}
