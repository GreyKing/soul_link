import { Controller } from "@hotwired/stimulus"

// Step 20 — Shared confirm-modal controller for destructive actions.
//
// Renders alongside the `app/views/shared/_confirm_modal.html.erb` partial.
// One controller instance per modal. Triggers (the destructive button on the
// page) call `confirm-modal#open` with `data-confirm-modal-id-param="<id>"`;
// we look up the matching modal in a process-wide registry and reveal it.
//
// ESC handling is provided globally by `escape_close_controller`, which
// clicks the `.gb-modal-close` button inside the topmost visible modal — that
// flows back through this controller's `close()` action. Focus trap is layered
// on top via `modal_a11y_controller` for the existing legacy modals; the
// confirm-modal partial bakes the same focus management directly into open()/
// close() below so it doesn't need a sibling controller.
export default class extends Controller {
  static values = { id: String }
  static targets = [ "cancel" ]

  connect() {
    if (!this.idValue) return
    if (typeof window !== "undefined") {
      window.__confirmModals = window.__confirmModals || {}
      window.__confirmModals[this.idValue] = this.element
    }

    this._priorFocus = null
    this._keydownHandler = this.#handleKeydown.bind(this)
  }

  disconnect() {
    if (typeof window !== "undefined" && window.__confirmModals) {
      delete window.__confirmModals[this.idValue]
    }
    document.removeEventListener("keydown", this._keydownHandler)
  }

  // Triggered by:
  //   <button data-action="click->confirm-modal#open"
  //           data-confirm-modal-id-param="end-run-confirm">END RUN</button>
  // The trigger is on a different element from the modal, but Stimulus still
  // routes the action to every connected `confirm-modal` controller; only the
  // one whose idValue matches the param will reveal itself.
  open(event) {
    const id = event.params?.id
    if (!id || id !== this.idValue) return

    event.preventDefault()
    this._priorFocus = document.activeElement
    this.element.classList.remove("hidden")

    // Focus the safe-default Cancel button. If the partial omitted it for
    // some reason (it shouldn't), fall back to the first focusable element
    // inside the modal so keyboard users still land somewhere sensible.
    const target = this.hasCancelTarget ? this.cancelTarget : this.#firstFocusable()
    target?.focus()

    document.addEventListener("keydown", this._keydownHandler)
  }

  close() {
    document.removeEventListener("keydown", this._keydownHandler)
    this.element.classList.add("hidden")

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

  // Wraps Tab/Shift-Tab focus inside the modal so the user can't accidentally
  // focus elements behind the dialog backdrop.
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
