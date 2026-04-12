import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["picker"]
  static values = {
    resultId: Number,
    updateUrl: String,
    csrf: String,
    groups: Array
  }

  openPicker() {
    this.selected = new Set()
    const picker = this.pickerTarget
    picker.replaceChildren()

    const grid = document.createElement("div")
    grid.style.cssText = "display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px; margin-top: 8px;"

    this.groupsValue.forEach(g => {
      const card = document.createElement("div")
      card.className = "gb-card-dark"
      card.style.cssText = "padding: 6px; text-align: center; cursor: pointer; font-size: 9px;"
      card.dataset.groupId = g.id

      const nick = document.createElement("div")
      nick.textContent = g.nickname
      nick.style.fontWeight = "bold"

      const spec = document.createElement("div")
      spec.textContent = g.species
      spec.style.cssText = "color: var(--d2); font-size: 8px;"

      card.append(nick, spec)
      card.addEventListener("click", () => this.toggleCard(card, g.id))
      grid.appendChild(card)
    })

    const saveBtn = document.createElement("button")
    saveBtn.className = "gb-btn-primary gb-btn-sm"
    saveBtn.style.cssText = "margin-top: 8px; font-size: 9px;"
    saveBtn.textContent = "SAVE TEAM"
    saveBtn.addEventListener("click", () => this.save())

    const cancelBtn = document.createElement("button")
    cancelBtn.className = "gb-btn gb-btn-sm"
    cancelBtn.style.cssText = "margin-top: 8px; margin-left: 6px; font-size: 9px;"
    cancelBtn.textContent = "CANCEL"
    cancelBtn.addEventListener("click", () => this.closePicker())

    const btnRow = document.createElement("div")
    btnRow.append(saveBtn, cancelBtn)

    picker.append(grid, btnRow)
    picker.classList.remove("hidden")
  }

  toggleCard(card, groupId) {
    if (this.selected.has(groupId)) {
      this.selected.delete(groupId)
      card.style.borderColor = ""
      card.style.background = ""
    } else {
      if (this.selected.size >= 6) return
      this.selected.add(groupId)
      card.style.borderColor = "var(--d1)"
      card.style.background = "var(--d2)"
    }
  }

  async save() {
    if (this.selected.size === 0) return

    const response = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
      body: JSON.stringify({ group_ids: Array.from(this.selected) })
    })

    if (response.ok) {
      window.location.reload()
    }
  }

  closePicker() {
    this.pickerTarget.classList.add("hidden")
    this.pickerTarget.replaceChildren()
  }
}
