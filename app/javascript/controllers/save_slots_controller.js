// Save slots column. The 5 slot cards are server-rendered; this controller
// wires up the per-card actions and the 409 → click-to-overwrite flow.
//
// Listens for two window events from the emulator controller:
//   - save-slots:saved          → page reload (server state changed)
//   - save-slots:overwrite-needed → arm overwrite-pending mode
//
// In overwrite-pending mode, each filled slot card shows a click overlay
// that, when clicked, calls window.EJS_emulator.gameManager.getSaveFile()
// to grab fresh SRAM bytes and PATCHes them to the chosen slot. Stateless
// — we don't stash bytes; we ask the emulator at click time. The Project
// Owner accepts that the SRAM at click time may differ slightly from the
// SRAM at the original Save File click (a few seconds of in-game drift).
import { Controller } from "@hotwired/stimulus"

const CONFIRM_DELETE = "Permanently delete this slot? This cannot be undone."
const CONFIRM_OVERWRITE = "Overwrite this slot with the save you just made? The current contents will be lost."

export default class extends Controller {
  static values = {
    slotsUrl: String,
    csrf: String,
    active: String
  }

  static targets = ["banner", "slot", "overwriteOverlay"]

  connect() {
    this._overwritePending = false
    this._onOverwriteNeeded = (event) => this._enterOverwriteMode(event)
    this._onSaved = () => this._refreshAfterSave()
    window.addEventListener("save-slots:overwrite-needed", this._onOverwriteNeeded)
    window.addEventListener("save-slots:saved", this._onSaved)
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
    if (!window.confirm(CONFIRM_DELETE)) return
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

  // --- overwrite flow -----------------------------------------------------

  _enterOverwriteMode(_event) {
    this._overwritePending = true
    if (this.hasBannerTarget) this.bannerTarget.hidden = false
    // Show the click-to-overwrite overlay only on FILLED slots — empty
    // slots are not a sensible overwrite target. The card's data-filled
    // attribute is rendered server-side based on whether a slot record
    // exists for that slot_number.
    this.slotTargets.forEach((card) => {
      if (card.dataset.filled !== "true") return
      const overlay = card.querySelector("[data-save-slots-target='overwriteOverlay']")
      if (overlay) overlay.hidden = false
    })
    // Disable the per-slot action buttons while overwrite mode is armed —
    // the overlay covers them visually, but tab navigation + screen readers
    // can still focus them. Without this, a misclick or stray Enter could
    // delete a slot the player only meant to overwrite.
    this._actionButtons().forEach((btn) => { btn.disabled = true })
  }

  _exitOverwriteMode() {
    this._overwritePending = false
    if (this.hasBannerTarget) this.bannerTarget.hidden = true
    this.overwriteOverlayTargets.forEach((overlay) => { overlay.hidden = true })
    this._actionButtons().forEach((btn) => { btn.disabled = false })
  }

  _actionButtons() {
    return this.element.querySelectorAll(
      "[data-action*='save-slots#makeActive'], [data-action*='save-slots#deleteSlot']"
    )
  }

  async overwriteSlot(event) {
    event.preventDefault()
    if (!this._overwritePending) return
    const slotNumber = event.currentTarget.dataset.slotNumber
    if (!slotNumber) return
    if (!window.confirm(CONFIRM_OVERWRITE)) return

    // Approach 2 (per the brief): grab fresh bytes from the running
    // emulator at click time. Stateless — no JS-side stash of the original
    // 409-triggering bytes. Project Owner accepts the small in-game drift.
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

  // --- post-save refresh --------------------------------------------------
  //
  // After a successful save (201 Created), reload so the slot column
  // re-renders with fresh server state. A future iteration could swap to a
  // partial fetch + DOM patch; for now, reload keeps the contract simple.
  _refreshAfterSave() {
    window.location.reload()
  }
}
