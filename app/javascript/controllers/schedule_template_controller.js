import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slotList", "slotRow", "hiddenInput"]

  connect() {
    this.sync()
  }

  addSlot() {
    if (this.slotRowTargets.length >= 5) return
    const idx = this.slotRowTargets.length
    const html = `
      <div class="slot-row" data-schedule-template-target="slotRow" data-index="${idx}">
        <select name="slot_day_${idx}" data-action="change->schedule-template#sync">
          <option value="1">Mon</option><option value="2">Tue</option><option value="3">Wed</option>
          <option value="4">Thu</option><option value="5">Fri</option><option value="6">Sat</option>
          <option value="7">Sun</option>
        </select>
        <input type="time" name="slot_time_${idx}" value="19:00" data-action="change->schedule-template#sync">
        <button type="button" data-action="click->schedule-template#removeSlot">Remove</button>
      </div>`
    this.slotListTarget.insertAdjacentHTML("beforeend", html)
    this.sync()
  }

  removeSlot(event) {
    event.target.closest(".slot-row").remove()
    this.sync()
  }

  sync() {
    const slots = this.slotRowTargets.map((row) => {
      const day = parseInt(row.querySelector("select").value, 10)
      const time = row.querySelector("input[type=time]").value
      return { day_of_week: day, time_of_day: time }
    })
    this.hiddenInputTarget.value = JSON.stringify({ slots })
  }
}
