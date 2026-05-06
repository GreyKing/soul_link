import { Controller } from "@hotwired/stimulus"

// Step 24 R1 — Run-pill dropdown for the dashboard title bar.
//
// Replaces the legacy `<select onchange="window.location.href=...">` that
// shipped inline JS (per audit annotation C). Each menu option is a real
// `<a href="/?run_id=N">` so the switch action works without JS — this
// controller only enhances the pill toggle + keyboard navigation.
//
// Targets:
//   trigger — the pill <button> with aria-haspopup="listbox".
//   menu    — the dropdown panel; toggled via the `hidden` class.
//   option  — every selectable run row (anchor or button).
//
// Keyboard contract:
//   ArrowDown / ArrowUp — move focus between options (with wrap)
//   Enter               — activate the focused option (link follows)
//   Escape              — close the menu, return focus to the trigger
export default class extends Controller {
  static targets = ["trigger", "menu", "option"]

  connect() {
    this._closeOnOutside = this._closeOnOutside.bind(this)
    document.addEventListener("click", this._closeOnOutside)
  }

  disconnect() {
    document.removeEventListener("click", this._closeOnOutside)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this._isOpen() ? this.close() : this.open()
  }

  open() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.remove("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "true")
    }
    // Focus the first option after the menu paints so screen readers
    // announce the active descendant.
    requestAnimationFrame(() => {
      const first = this.optionTargets[0]
      if (first) first.focus()
    })
  }

  close() {
    if (!this.hasMenuTarget) return
    this.menuTarget.classList.add("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
  }

  // Bound to keydown on the wrapper element. Captures arrow / enter / esc
  // for both the pill and the open menu.
  navigate(event) {
    const open = this._isOpen()

    if (event.key === "Escape" && open) {
      event.preventDefault()
      this.close()
      if (this.hasTriggerTarget) this.triggerTarget.focus()
      return
    }

    if (!open) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        this.open()
      }
      return
    }

    const options = this.optionTargets
    if (options.length === 0) return
    const currentIndex = options.indexOf(document.activeElement)

    if (event.key === "ArrowDown") {
      event.preventDefault()
      // When the trigger (not an option) has focus, currentIndex === -1.
      // ArrowDown should land on the first option, not on options[0]
      // by way of `(-1 + 1) % n`. (That happens to work, but be explicit.)
      if (currentIndex === -1) {
        options[0].focus()
      } else {
        const next = options[(currentIndex + 1) % options.length]
        next.focus()
      }
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      // When the trigger (not an option) has focus, currentIndex === -1.
      // The naive `(-1 - 1 + n) % n` lands on `n - 2` (second-to-last).
      // The WAI-ARIA contract says ArrowUp from the trigger should land
      // on the last option.
      if (currentIndex === -1) {
        options[options.length - 1].focus()
      } else {
        const prev = options[(currentIndex - 1 + options.length) % options.length]
        prev.focus()
      }
    } else if (event.key === "Home") {
      event.preventDefault()
      options[0].focus()
    } else if (event.key === "End") {
      event.preventDefault()
      options[options.length - 1].focus()
    } else if (event.key === "Enter" && currentIndex >= 0) {
      // Anchors trigger natively; for non-anchor options we click().
      const target = options[currentIndex]
      if (target.tagName !== "A") {
        event.preventDefault()
        target.click()
      }
    }
  }

  _isOpen() {
    return this.hasMenuTarget && !this.menuTarget.classList.contains("hidden")
  }

  _closeOnOutside(event) {
    if (!this._isOpen()) return
    if (this.element.contains(event.target)) return
    this.close()
  }
}
