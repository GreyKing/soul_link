import { Controller } from "@hotwired/stimulus"

// One reusable, position:fixed popup for any descendant carrying
// `data-ability-full`. Mounted once high in the tree; uses mouseover/
// mouseout delegation (both bubble) so it also covers elements created
// later by JS (dropdown options, linked-pokemon cards). Hover-only —
// matching the nature label, which has no keyboard/tooltip treatment
// either; the annotated elements are non-focusable, so focus events
// would be dead code.
export default class extends Controller {
  connect() {
    this._popup = null
    this._onOver = (e) => this.#maybeShow(e.target)
    this._onOut = (e) => this.#maybeHide(e.target, e.relatedTarget)
    this.element.addEventListener("mouseover", this._onOver)
    this.element.addEventListener("mouseout", this._onOut)
  }

  disconnect() {
    this.element.removeEventListener("mouseover", this._onOver)
    this.element.removeEventListener("mouseout", this._onOut)
    this.#destroyPopup()
  }

  #maybeShow(target) {
    const host = target?.closest?.("[data-ability-full]")
    if (!host) return
    const text = host.getAttribute("data-ability-full")
    if (!text) return
    this.#show(host, text)
  }

  #maybeHide(target, related) {
    const host = target?.closest?.("[data-ability-full]")
    if (!host) return
    // Ignore moves that stay within the same host element.
    if (related && host.contains(related)) return
    this.#hide()
  }

  #show(host, text) {
    const popup = this.#ensurePopup()
    popup.textContent = text
    popup.style.visibility = "hidden"
    popup.style.display = "block"

    const rect = host.getBoundingClientRect()
    const pr = popup.getBoundingClientRect()
    // Prefer above; flip below if it would clip the viewport top,
    // then clamp into the viewport on both axes.
    let top = rect.top - pr.height - 6
    if (top < 4) top = rect.bottom + 6
    const maxTop = window.innerHeight - pr.height - 4
    if (top > maxTop) top = Math.max(4, maxTop)
    let left = rect.left
    const maxLeft = window.innerWidth - pr.width - 4
    if (left > maxLeft) left = Math.max(4, maxLeft)

    popup.style.top = `${Math.round(top)}px`
    popup.style.left = `${Math.round(left)}px`
    popup.style.visibility = "visible"
  }

  #hide() {
    if (this._popup) this._popup.style.display = "none"
  }

  #ensurePopup() {
    if (!this._popup) {
      this._popup = document.createElement("div")
      this._popup.className = "gb-tooltip"
      this._popup.setAttribute("role", "tooltip")
      document.body.appendChild(this._popup)
    }
    return this._popup
  }

  #destroyPopup() {
    if (this._popup) {
      this._popup.remove()
      this._popup = null
    }
  }
}
