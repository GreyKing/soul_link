// Save slots column. The 5 slot cards are server-rendered; this controller
// wires up the per-card actions and the 409 → click-to-overwrite flow.
//
// Listens for two window events from the emulator controller:
//   - save-slots:saved          → page reload (server state changed)
//   - save-slots:overwrite-needed → arm overwrite-pending mode
//
// Step 21 R3 redesign:
//   - DELETE / CLEAR ALL SLOTS use inline confirm (not the Step-20 modal).
//     The slot's `.slot-actions` row hides + the sibling `.confirm-inline`
//     reveals; the slot's state pill flips to red CONFIRM. CANCEL reverts.
//   - Overwrite-pending mode: per-slot overlay buttons removed. Each filled
//     slot is itself the click target (amber TARGET pill + amber border +
//     wrapper-level click action). The sticky `.pending-banner` carries the
//     CANCEL button. No native window.confirm — the banner is the
//     announcement, the click is the consent.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    slotsUrl: String,
    csrf: String,
    active: String
  }

  static targets = [
    "banner",
    "slot",
    "slotPill",
    "actionRow",
    "confirmRow",
    "clearAllAction",
    "clearAllConfirm"
  ]

  connect() {
    this._overwritePending = false
    this._onOverwriteNeeded = (event) => this._enterOverwriteMode(event)
    this._onSaved = () => this._refreshAfterSave()
    window.addEventListener("save-slots:overwrite-needed", this._onOverwriteNeeded)
    window.addEventListener("save-slots:saved", this._onSaved)

    // Cache each slot pill's original class + text on its dataset so
    // _exitOverwriteMode and cancelDelete can restore them. Survives
    // broadcast replacements better than a JS WeakMap because the value
    // travels with the rendered DOM.
    this.slotPillTargets.forEach((pill) => {
      if (!pill.dataset.originalPillClass) {
        pill.dataset.originalPillClass = pill.className
      }
      if (!pill.dataset.originalPillText) {
        pill.dataset.originalPillText = pill.textContent
      }
    })
  }

  disconnect() {
    window.removeEventListener("save-slots:overwrite-needed", this._onOverwriteNeeded)
    window.removeEventListener("save-slots:saved", this._onSaved)
  }

  // --- per-slot actions ---------------------------------------------------

  async makeActive(event) {
    event.preventDefault()
    const slotNumber = event.currentTarget.dataset.slotNumber
    if (!slotNumber) return
    try {
      const res = await fetch(`${this.slotsUrlValue}/${slotNumber}/restore`, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfValue },
        credentials: "same-origin"
      })
      if (!res.ok) {
        console.error("SaveSlots: restore failed:", res.status)
        window.alert(`Could not make slot ${slotNumber} active. Try again or contact the run creator.`)
        return
      }
      window.alert(`Slot ${slotNumber} is now active. Refresh the page to load it.`)
    } catch (e) {
      console.error("SaveSlots: restore error:", e)
      window.alert(`Network error making slot ${slotNumber} active. Try again or contact the run creator.`)
    }
  }

  async deleteSlot(event) {
    event.preventDefault()
    const slotNumber = event.currentTarget.dataset.slotNumber
    if (!slotNumber) return
    try {
      const res = await fetch(`${this.slotsUrlValue}/${slotNumber}`, {
        method: "DELETE",
        headers: { "X-CSRF-Token": this.csrfValue },
        credentials: "same-origin"
      })
      if (!res.ok) {
        console.error("SaveSlots: delete failed:", res.status)
        window.alert(`Could not delete slot ${slotNumber}. Try again or contact the run creator.`)
        return
      }
      window.location.reload()
    } catch (e) {
      console.error("SaveSlots: delete error:", e)
      window.alert(`Network error deleting slot ${slotNumber}. Try again or contact the run creator.`)
    }
  }

  // --- inline DELETE confirm ----------------------------------------------

  confirmDelete(event) {
    event.preventDefault()
    const slot = this._slotForEvent(event)
    if (!slot) return
    const actionRow = slot.querySelector("[data-save-slots-target='actionRow']")
    const confirmRow = slot.querySelector("[data-save-slots-target='confirmRow']")
    const pill = slot.querySelector("[data-save-slots-target='slotPill']")
    if (actionRow) actionRow.hidden = true
    if (confirmRow) {
      confirmRow.hidden = false
      // Focus the cancel button — safe-default keyboard behavior the
      // mockup annotation calls out (ENTER targets cancel).
      const cancel = confirmRow.querySelector("[data-action*='save-slots#cancelDelete']")
      if (cancel) cancel.focus()
    }
    if (pill) {
      pill.className = "state-pill confirm"
      pill.textContent = "CONFIRM"
    }
  }

  cancelDelete(event) {
    event.preventDefault()
    const slot = this._slotForEvent(event)
    if (!slot) return
    const actionRow = slot.querySelector("[data-save-slots-target='actionRow']")
    const confirmRow = slot.querySelector("[data-save-slots-target='confirmRow']")
    const pill = slot.querySelector("[data-save-slots-target='slotPill']")
    if (confirmRow) confirmRow.hidden = true
    if (actionRow) actionRow.hidden = false
    if (pill && pill.dataset.originalPillClass) {
      pill.className = pill.dataset.originalPillClass
      pill.textContent = pill.dataset.originalPillText
    }
  }

  // --- inline CLEAR ALL SLOTS confirm -------------------------------------

  confirmClearAll(event) {
    event.preventDefault()
    if (this.hasClearAllActionTarget) this.clearAllActionTarget.hidden = true
    if (this.hasClearAllConfirmTarget) {
      this.clearAllConfirmTarget.hidden = false
      const cancel = this.clearAllConfirmTarget.querySelector("[data-action*='save-slots#cancelClearAll']")
      if (cancel) cancel.focus()
    }
  }

  cancelClearAll(event) {
    event.preventDefault()
    if (this.hasClearAllConfirmTarget) this.clearAllConfirmTarget.hidden = true
    if (this.hasClearAllActionTarget) this.clearAllActionTarget.hidden = false
  }

  // --- overwrite flow -----------------------------------------------------

  _enterOverwriteMode(_event) {
    this._overwritePending = true
    if (this.hasBannerTarget) this.bannerTarget.hidden = false

    // Walk filled slots: amber TARGET pill, amber border via
    // .overwrite-target, wrapper becomes the click target, hide the
    // per-slot action row.
    this.slotTargets.forEach((slot) => {
      if (slot.dataset.filled !== "true") return
      slot.classList.add("overwrite-target")
      slot.setAttribute("data-action", "click->save-slots#overwriteSlot")
      // Reconcile any in-flight inline DELETE confirm on this slot before
      // arming overwrite mode — otherwise the slot reads as both
      // "confirm delete?" and amber TARGET, and the cached pill restores
      // to SAVED (not the in-flight CONFIRM) on exit.
      const confirmRow = slot.querySelector("[data-save-slots-target='confirmRow']")
      if (confirmRow) confirmRow.hidden = true
      const actionRow = slot.querySelector("[data-save-slots-target='actionRow']")
      if (actionRow) actionRow.hidden = true
      const pill = slot.querySelector("[data-save-slots-target='slotPill']")
      if (pill) {
        pill.className = "state-pill target"
        pill.textContent = "TARGET"
      }
    })

    // Disable the per-slot action buttons — overlay is gone but tab
    // navigation could still focus them otherwise.
    this._actionButtons().forEach((btn) => { btn.disabled = true })
  }

  _exitOverwriteMode() {
    this._overwritePending = false
    if (this.hasBannerTarget) this.bannerTarget.hidden = true

    this.slotTargets.forEach((slot) => {
      if (slot.dataset.filled !== "true") return
      slot.classList.remove("overwrite-target")
      slot.removeAttribute("data-action")
      const actionRow = slot.querySelector("[data-save-slots-target='actionRow']")
      if (actionRow) actionRow.hidden = false
      const pill = slot.querySelector("[data-save-slots-target='slotPill']")
      if (pill && pill.dataset.originalPillClass) {
        pill.className = pill.dataset.originalPillClass
        pill.textContent = pill.dataset.originalPillText
      }
    })

    this._actionButtons().forEach((btn) => { btn.disabled = false })
  }

  cancelOverwrite(event) {
    if (event) event.preventDefault()
    this._exitOverwriteMode()
  }

  _actionButtons() {
    // Step 21 — DELETE trigger now fires the inline-confirm action
    // (save-slots#confirmDelete) instead of opening the Step-20 modal.
    // Match THAT selector so overwrite-pending mode still disables it.
    return this.element.querySelectorAll(
      "[data-action*='save-slots#makeActive'], [data-action*='save-slots#confirmDelete']"
    )
  }

  async overwriteSlot(event) {
    event.preventDefault()
    if (!this._overwritePending) return
    const slotNumber = event.currentTarget.dataset.slotNumber
    if (!slotNumber) return

    // Step 21 — no native window.confirm here. The banner is the
    // announcement; clicking a TARGET slot is the explicit consent.
    //
    // Approach 2 (per Step-3 brief): grab fresh bytes from the running
    // emulator at click time. Stateless — no JS-side stash of the
    // 409-triggering bytes. Project Owner accepts the small in-game
    // drift.
    let bytes = null
    try {
      const emu = window.EJS_emulator
      if (emu && emu.gameManager && typeof emu.gameManager.getSaveFile === "function") {
        bytes = emu.gameManager.getSaveFile()
      }
    } catch (e) {
      console.error("SaveSlots: failed to read emulator save:", e)
    }
    if (!bytes || bytes.byteLength === 0) {
      window.alert("Could not read the current save from the emulator. Try clicking 'Save File' again.")
      return
    }

    const blob = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
    try {
      const res = await fetch(`${this.slotsUrlValue}/${slotNumber}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/octet-stream",
          "X-CSRF-Token": this.csrfValue
        },
        credentials: "same-origin",
        body: blob
      })
      if (!res.ok) {
        console.error("SaveSlots: overwrite PATCH failed:", res.status)
        window.alert("Could not overwrite the slot. Try again or contact the run creator.")
        return
      }
      this._exitOverwriteMode()
      window.location.reload()
    } catch (e) {
      console.error("SaveSlots: overwrite error:", e)
      window.alert("Network error overwriting the slot. Try again or contact the run creator.")
    }
  }

  // --- helpers ------------------------------------------------------------

  _slotForEvent(event) {
    const slotNumber = event.currentTarget.dataset.slotNumber
    if (!slotNumber) return null
    return this.slotTargets.find((s) => s.dataset.slotNumber === slotNumber)
  }

  // --- post-save refresh --------------------------------------------------
  //
  // After a successful save (201 Created), reload so the slot column
  // re-renders with fresh server state. A future iteration could swap to
  // a partial fetch + DOM patch; for now, reload keeps the contract simple.
  _refreshAfterSave() {
    window.location.reload()
  }
}
