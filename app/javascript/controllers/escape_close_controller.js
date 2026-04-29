import { Controller } from "@hotwired/stimulus"

// Closes the topmost visible modal when Escape is pressed.
// Attached once at the layout level (data-controller="escape-close" on <body>).
// Works by clicking the visible .gb-modal-close button, which routes through
// each modal's own close action — so each controller still owns its teardown.
export default class extends Controller {
  connect() {
    this._handler = this.handleEscape.bind(this)
    document.addEventListener("keydown", this._handler)
  }

  disconnect() {
    document.removeEventListener("keydown", this._handler)
  }

  handleEscape(event) {
    if (event.key !== "Escape") return

    const closeButtons = Array.from(document.querySelectorAll(".gb-modal-close"))
    const visibleButton = closeButtons.find((btn) => this.#isVisible(btn))

    if (visibleButton) {
      event.preventDefault()
      visibleButton.click()
    }
  }

  // Walks up the DOM checking for a .hidden ancestor. Modals toggle visibility
  // via .hidden on a wrapper, not display:none on the close button itself.
  #isVisible(el) {
    let node = el
    while (node) {
      if (node.classList && node.classList.contains("hidden")) return false
      node = node.parentElement
    }
    return true
  }
}
