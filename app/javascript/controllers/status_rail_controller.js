import { Controller } from "@hotwired/stimulus"

// Step 24 R1 — Right-rail sub-tab switcher (PARTY / GYMS / MAP).
//
// The wrapping `<aside class="status-rail">` is the controller element.
// `tabButton` targets carry `data-status-rail-tab-param="<key>"` and
// `tabPanel` targets carry `data-status="<key>"`. Activating a tab flips
// `aria-selected` + `tabindex` on every button and toggles the matching
// panel's `.hidden` class.
//
// Keyboard contract on the sub-tablist:
//   ArrowLeft / ArrowRight — move focus + activate, wraps at edges
//   Home / End             — first / last sub-tab
export default class extends Controller {
  static targets = ["tabButton", "tabPanel"]

  switch(event) {
    const button = event.currentTarget
    const tab = button.dataset.statusRailTabParam || button.dataset.tab
    if (!tab) return
    this._activate(tab, { focus: false })
  }

  keydown(event) {
    const buttons = this.tabButtonTargets
    if (buttons.length === 0) return
    const currentIndex = buttons.indexOf(document.activeElement)
    if (currentIndex === -1) return

    let nextIndex = null
    switch (event.key) {
      case "ArrowRight":
        nextIndex = (currentIndex + 1) % buttons.length
        break
      case "ArrowLeft":
        nextIndex = (currentIndex - 1 + buttons.length) % buttons.length
        break
      case "Home":
        nextIndex = 0
        break
      case "End":
        nextIndex = buttons.length - 1
        break
      default:
        return
    }
    event.preventDefault()
    const tab = buttons[nextIndex].dataset.statusRailTabParam || buttons[nextIndex].dataset.tab
    if (tab) this._activate(tab, { focus: true })
  }

  _activate(tab, { focus }) {
    this.tabButtonTargets.forEach(btn => {
      const key = btn.dataset.statusRailTabParam || btn.dataset.tab
      const isActive = key === tab
      btn.setAttribute("aria-selected", isActive ? "true" : "false")
      btn.setAttribute("tabindex", isActive ? "0" : "-1")
      if (isActive && focus) btn.focus()
    })
    this.tabPanelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.status !== tab)
    })
  }
}
