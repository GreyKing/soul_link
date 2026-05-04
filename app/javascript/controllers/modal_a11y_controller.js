import { Controller } from "@hotwired/stimulus"

// Step 20 — Modal accessibility helper for the seven existing legacy modals
// (catch, pokemon, mark-dead, reset-draft, group, coin-flip, quick-calc).
// The new shared confirm_modal partial bakes the same focus management into
// confirm_modal_controller.js directly; this controller is for modals that
// already have parent open/close logic owned by another Stimulus controller.
//
// Layered behavior:
//   - ARIA `role="dialog"` / `aria-modal="true"` / `aria-labelledby` are set
//     statically on the modal partial (markup only — no JS needed).
//   - ESC-to-close is provided globally by `escape_close_controller`, which
//     clicks the topmost `.gb-modal-close` button.
//   - This controller adds the focus trap (Tab / Shift-Tab wrap) and
//     focus-restore-on-close, which are not provided by the global helper.
//
// Wiring per modal:
//   <div class="gb-modal" role="dialog" aria-modal="true"
//        aria-labelledby="catch-modal-title"
//        data-controller="modal-a11y">
//     ... close button needs no special target — focus restore happens on
//         class="hidden" being added to the modal's wrapper element.
//
// The wrapper element (the outer `position: fixed` div toggling `.hidden`)
// is a few levels up the tree from this controller's element. We walk to
// `.closest("[class*='hidden']")` ancestor on connect to find it; if no
// suitable wrapper exists we fall back to watching this element itself.
export default class extends Controller {
  connect() {
    this._wrapper = this.#findWrapper()
    this._priorFocus = null
    this._keydownHandler = this.#handleKeydown.bind(this)

    this._observer = new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.type !== "attributes" || m.attributeName !== "class") continue
        const isHiddenNow = this._wrapper.classList.contains("hidden")
        if (this._wasHidden === undefined) {
          this._wasHidden = isHiddenNow
          continue
        }
        if (this._wasHidden && !isHiddenNow) {
          this.#onOpen()
        } else if (!this._wasHidden && isHiddenNow) {
          this.#onClose()
        }
        this._wasHidden = isHiddenNow
      }
    })
    this._observer.observe(this._wrapper, { attributes: true, attributeFilter: ["class"] })
    this._wasHidden = this._wrapper.classList.contains("hidden")
  }

  disconnect() {
    if (this._observer) this._observer.disconnect()
    document.removeEventListener("keydown", this._keydownHandler)
  }

  #findWrapper() {
    // The wrapper is the closest ancestor that toggles `.hidden`. Most modals
    // in this codebase wrap the gb-modal in a `position: fixed` div that gets
    // class="hidden" toggled. If no ancestor has `.hidden` initially, fall
    // back to scanning two levels up; otherwise use this.element itself.
    let node = this.element.parentElement
    while (node && node !== document.body) {
      // Heuristic: a wrapper is a fixed-position div that may carry .hidden.
      // We accept the first ancestor matching either condition.
      const style = node.getAttribute("style") || ""
      if (node.classList.contains("hidden") || /position:\s*fixed/i.test(style)) {
        return node
      }
      node = node.parentElement
    }
    return this.element
  }

  #onOpen() {
    this._priorFocus = document.activeElement
    const first = this.#firstFocusable()
    first?.focus()
    document.addEventListener("keydown", this._keydownHandler)
  }

  #onClose() {
    document.removeEventListener("keydown", this._keydownHandler)
    if (this._priorFocus && typeof this._priorFocus.focus === "function") {
      this._priorFocus.focus()
    }
    this._priorFocus = null
  }

  #handleKeydown(event) {
    if (event.key === "Tab") {
      this.#trapTab(event)
    }
  }

  #trapTab(event) {
    const focusables = this.#focusables()
    if (focusables.length === 0) return

    const first = focusables[0]
    const last = focusables[focusables.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }

  #focusables() {
    return Array.from(
      this.element.querySelectorAll(
        'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.hasAttribute("hidden") && el.offsetParent !== null)
  }

  #firstFocusable() {
    return this.#focusables()[0]
  }
}
