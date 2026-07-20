import { Controller } from "@hotwired/stimulus"

// Generic filtered combobox. Written option-agnostic so the species field
// can adopt it later without a rewrite.
//
// The full option list ships inline — for abilities that is 123 strings,
// roughly 3KB, far cheaper than an endpoint round-trip per keystroke.
export default class extends Controller {
  static targets = ["input", "list", "hidden"]
  static values = {
    options: Array,
    visibleCount: { type: Number, default: 5 }
  }

  connect() {
    this._activeIndex = -1
    this._filtered = []
    this._open = false
    // Unique per instance — a second searchable-select on the page would
    // otherwise emit duplicate option ids and break aria-activedescendant.
    this._uid = `ss-${Math.random().toString(36).slice(2, 9)}`
    this.listTarget.id = `${this._uid}-list`
    this.inputTarget.setAttribute("aria-controls", this.listTarget.id)
    this.listTarget.style.setProperty("--visible-count", String(this.visibleCountValue))
    this.close()
  }

  // Set the value programmatically (used when a modal opens with a stored
  // ability). Updates both the visible input and the hidden field.
  setValue(value) {
    this.inputTarget.value = value || ""
    this.hiddenTarget.value = value || ""
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    this._filtered = query
      ? this.optionsValue.filter((o) => o.toLowerCase().includes(query))
      : [...this.optionsValue]
    this._activeIndex = this._filtered.length > 0 ? 0 : -1
    this.#render()
    this.open()
  }

  open() {
    this._open = true
    this.listTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this._open = false
    this.listTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  // Delay so a click on an option lands before the list is hidden.
  closeSoon() {
    this._blurTimer = setTimeout(() => this.close(), 150)
  }

  cancelClose() {
    if (this._blurTimer) clearTimeout(this._blurTimer)
  }

  selectOption(event) {
    this.#commit(event.currentTarget.dataset.value)
  }

  keydown(event) {
    if (!this._open && ["ArrowDown", "ArrowUp"].includes(event.key)) {
      this.filter()
      return
    }
    if (!this._open) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.#move(1)
        break
      case "ArrowUp":
        event.preventDefault()
        this.#move(-1)
        break
      case "Enter":
        if (this._activeIndex >= 0) {
          event.preventDefault()
          this.#commit(this._filtered[this._activeIndex])
        }
        break
      case "Escape":
        // Swallow so the global escape-close controller does not also tear
        // down the surrounding modal — one Escape closes one thing.
        event.preventDefault()
        event.stopPropagation()
        this.close()
        break
    }
  }

  #commit(value) {
    if (value === undefined || value === null) return
    this.inputTarget.value = value
    this.hiddenTarget.value = value
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }

  #move(delta) {
    if (this._filtered.length === 0) return
    this._activeIndex =
      (this._activeIndex + delta + this._filtered.length) % this._filtered.length
    this.#render()
    this.listTarget.children[this._activeIndex]?.scrollIntoView({ block: "nearest" })
  }

  #render() {
    this.listTarget.replaceChildren()

    if (this._filtered.length === 0) {
      const empty = document.createElement("li")
      empty.textContent = "No matches"
      empty.className = "searchable-select-empty"
      this.listTarget.appendChild(empty)
      return
    }

    this._filtered.forEach((option, index) => {
      const li = document.createElement("li")
      li.textContent = option
      li.dataset.value = option
      li.id = `${this._uid}-opt-${index}`
      li.setAttribute("role", "option")
      li.setAttribute("aria-selected", String(index === this._activeIndex))
      li.className =
        "searchable-select-option" + (index === this._activeIndex ? " is-active" : "")
      li.setAttribute("data-action", "mousedown->searchable-select#selectOption")
      this.listTarget.appendChild(li)
    })

    const active = this.listTarget.children[this._activeIndex]
    if (active) this.inputTarget.setAttribute("aria-activedescendant", active.id)
  }
}
