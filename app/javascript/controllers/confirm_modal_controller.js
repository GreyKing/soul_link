import { Controller } from "@hotwired/stimulus"

// Step 20 — Shared confirm-modal controller for destructive actions.
//
// Rendered by the `app/views/shared/_confirm_modal.html.erb` partial, which
// wraps the caller's trigger AND the dialog in one controller element. One
// controller instance therefore owns exactly one trigger/dialog pair: the
// trigger calls `confirm-modal#open` and we reveal `dialogTarget`. There is
// no id matching and no registry — scoping alone decides which dialog opens.
//
// ESC handling is provided globally by `escape_close_controller`, which
// clicks the `.gb-modal-close` button inside the topmost visible modal — that
// flows back through this controller's `close()` action. Focus trap is layered
// on top via `modal_a11y_controller` for the existing legacy modals; the
// confirm-modal partial bakes the same focus management directly into open()/
// close() below so it doesn't need a sibling controller.
export default class extends Controller {
  static targets = [ "cancel", "dialog" ]

  connect() {
    this._priorFocus = null
    this._keydownHandler = this.#handleKeydown.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this._keydownHandler)
  }

  // Triggered by the trigger button, which `ConfirmModalHelper#confirm_modal`
  // renders INSIDE this controller's element:
  //   <div data-controller="confirm-modal" style="display: contents">
  //     <button data-action="click->confirm-modal#open">END RUN</button>
  //     <div data-confirm-modal-target="dialog" class="hidden">…</div>
  //   </div>
  //
  // One controller instance per trigger/dialog pair, so there is no id to
  // match on — the action can only reach the dialog it belongs to. An earlier
  // version rendered the trigger as a sibling of the dialog and relied on
  // Stimulus broadcasting the action to every connected `confirm-modal`
  // controller. Stimulus does not do that: it routes to the closest ancestor
  // controller only, so the click was silently dropped and the dialog could
  // never open.
  open(event) {
    event.preventDefault()
    this._priorFocus = document.activeElement
    this.dialogTarget.classList.remove("hidden")

    // Focus the safe-default Cancel button. If the partial omitted it for
    // some reason (it shouldn't), fall back to the first focusable element
    // inside the modal so keyboard users still land somewhere sensible.
    const target = this.hasCancelTarget ? this.cancelTarget : this.#firstFocusable()
    target?.focus()

    document.addEventListener("keydown", this._keydownHandler)
  }

  close() {
    document.removeEventListener("keydown", this._keydownHandler)
    this.dialogTarget.classList.add("hidden")

    if (this._priorFocus && typeof this._priorFocus.focus === "function") {
      this._priorFocus.focus()
    }
    this._priorFocus = null
  }

  // The dimming backdrop sits *behind* the centering wrapper (both z-index
  // auto, wrapper paints later), so clicks in the empty area never reach it.
  // The wrapper carries the close action instead; this guard ignores clicks
  // that bubbled up from the modal card.
  closeOnBackdrop(event) {
    if (event.target !== event.currentTarget) return
    this.close()
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

  // Scoped to the dialog, NOT to this.element — the controller element also
  // contains the trigger button, and including it would let Tab walk out of
  // the open dialog and back onto the control that opened it.
  #focusables() {
    return Array.from(
      this.dialogTarget.querySelectorAll(
        'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )
    ).filter((el) => !el.hasAttribute("hidden") && el.offsetParent !== null)
  }

  #firstFocusable() {
    return this.#focusables()[0]
  }
}
