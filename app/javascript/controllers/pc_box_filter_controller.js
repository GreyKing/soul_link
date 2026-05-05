import { Controller } from "@hotwired/stimulus"

// Step 22 R2 — chip filter + free-text search + URL hash for the PC BOX
// unified grid. State lives in `this.status` / `this.search`; URL hash
// (`#team`, `#storage`, `#fallen`, `#all`) preserves filter state across
// reloads. Stimulus re-instantiates on Turbo morph; `connect()` re-applies
// the hash, so state survives broadcast refreshes too.
export default class extends Controller {
  static targets = [ "chip", "cell", "searchInput", "rail", "count" ]
  static values = { total: Number }

  connect() {
    this.search = ""
    const hashStatus = (window.location.hash || "").replace(/^#/, "")
    this.status = [ "all", "team", "storage", "fallen" ].includes(hashStatus) ? hashStatus : "all"
    if (this.hasSearchInputTarget) this.searchInputTarget.value = ""
    // Cache the ERB-rendered count text so we can restore it when filter
    // returns to ALL + empty search (the ERB carries the "ALL CAUGHT-UP"
    // / "K NEW PARSED" suffix that the JS doesn't know about).
    this._defaultCountText = this.hasCountTarget ? this.countTarget.textContent : ""
    this._render()
  }

  applyFilter(event) {
    const status = event.params?.status || event.currentTarget?.dataset?.status || "all"
    this.status = status
    if (status === "all") {
      history.replaceState(null, "", window.location.pathname + window.location.search)
    } else {
      window.location.hash = `#${status}`
    }
    this._render()
  }

  applySearch(event) {
    clearTimeout(this._searchDebounce)
    const value = (event.target.value || "").toLowerCase().trim()
    this._searchDebounce = setTimeout(() => {
      this.search = value
      this._render()
    }, 150)
  }

  _render() {
    let visible = 0
    this.cellTargets.forEach((cell) => {
      const cellStatus = cell.dataset.status
      const haystack = cell.dataset.searchHaystack || ""
      const filterMatch = this.status === "all" || cellStatus === this.status
      const searchMatch = this.search.length === 0 || haystack.includes(this.search)
      const show = filterMatch && searchMatch
      cell.classList.toggle("filter-hidden", !filterMatch)
      cell.classList.toggle("search-hidden", filterMatch && !searchMatch)
      if (show) visible += 1
    })

    this.chipTargets.forEach((chip) => {
      const isActive = (chip.dataset.status || "all") === this.status
      chip.classList.toggle("active", isActive)
    })

    // Mockup Screen 2: when a non-ALL filter is active, dim the inactive
    // chips. CSS rule .pc-box-r2.filter-active .filter-chip:not(.active)
    // owns the visual; the controller just toggles the parent class.
    this.element.classList.toggle("filter-active", this.status !== "all")

    if (this.hasRailTarget) {
      const dimRail = this.status !== "all" && this.status !== "team"
      this.railTarget.classList.toggle("dimmed", dimRail)
    }

    if (this.hasCountTarget) {
      const total = this.totalValue || this.cellTargets.length
      if (this.status === "all" && this.search.length === 0) {
        this.countTarget.textContent = this._defaultCountText
      } else {
        this.countTarget.textContent = `${visible} OF ${total} SHOWN`
      }
    }
  }
}
