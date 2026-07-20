import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Drag a living Pokemon from the PC box into the party sidebar.
//
// Dropping onto an occupied slot SWAPS: the resident leaves the party and
// the dragged group takes its position.
//
// The dragged node is a *clone of a .box-cell*, not a .team-slot, so we read
// its group id from the dataset and discard the node — then reload, because
// party slot markup carries seven data-group-* attributes that the detail
// modal depends on, and rebuilding that client-side would duplicate view
// logic. Party edits are infrequent; a reload is the honest trade.
export default class extends Controller {
  static targets = ["boxGrid", "partyList"]
  static values = { updateUrl: String, csrf: String }

  static MAX_SLOTS = 6

  connect() {
    if (!this.hasBoxGridTarget || !this.hasPartyListTarget) return

    this._boxSortable = new Sortable(this.boxGridTarget, {
      group: { name: "party", pull: "clone", put: false },
      sort: false,
      // Dead Pokemon never start a drag, so the gesture cannot appear to
      // succeed and then snap back.
      filter: "[data-alive='false']",
      onStart: () => document.body.classList.add("sortable-dragging"),
      onEnd: () => {
        setTimeout(() => document.body.classList.remove("sortable-dragging"), 0)
      }
    })

    this._partySortable = new Sortable(this.partyListTarget, {
      group: { name: "party", pull: false, put: true },
      draggable: ".team-slot",
      onAdd: (event) => this.#handleDrop(event)
    })
  }

  disconnect() {
    this._boxSortable?.destroy()
    this._partySortable?.destroy()
  }

  #handleDrop(event) {
    const item = event.item
    const groupId = item.dataset.groupId

    // Count real party slots preceding the drop point. Empty placeholders
    // use .team-slot-empty and must not be counted.
    let insertAt = 0
    for (let node = item.previousElementSibling; node; node = node.previousElementSibling) {
      if (node.classList.contains("team-slot")) insertAt++
    }

    item.remove() // discard the .box-cell clone; server render is the truth

    if (!groupId) return

    const current = Array.from(this.partyListTarget.querySelectorAll(".team-slot"))
      .map((el) => el.dataset.groupId)
      .filter(Boolean)

    if (current.includes(groupId)) return // already in the party

    const ids = [...current]
    const MAX = this.constructor.MAX_SLOTS

    if (ids.length >= MAX) {
      // Swap: the resident at the drop position is displaced.
      ids[Math.min(insertAt, MAX - 1)] = groupId
    } else {
      ids.splice(insertAt, 0, groupId)
    }

    this.#persist(ids)
  }

  #persist(ids) {
    fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfValue
      },
      body: JSON.stringify({ group_ids: ids })
    })
      .then((r) => r.json())
      .then((data) => {
        if (data.error) console.warn("Party update rejected:", data.error)
        window.location.reload()
      })
      .catch(() => window.location.reload())
  }
}
