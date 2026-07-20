import { Controller } from "@hotwired/stimulus"

// Click → POST → poll → download link. Generation takes up to 30s (Java
// subprocess), far too long to hold an HTTP request open, so the work is
// queued and this polls for the result.
export default class extends Controller {
  static targets = ["button", "status", "link"]
  static values = { runId: Number, pollInterval: { type: Number, default: 2000 } }

  disconnect() {
    this.#stopPolling()
  }

  generate() {
    this.buttonTarget.disabled = true
    this.#setStatus("Generating ROM…")
    this.linkTarget.classList.add("hidden")

    fetch(`/runs/${this.runIdValue}/rom_downloads`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      }
    })
      .then((r) => r.json())
      .then((data) => {
        if (!data.id) throw new Error("no download id")
        this._downloadId = data.id
        this.#startPolling()
      })
      .catch(() => this.#fail("Could not start generation."))
  }

  #startPolling() {
    this.#stopPolling()
    this._timer = setInterval(() => this.#poll(), this.pollIntervalValue)
  }

  #stopPolling() {
    if (this._timer) clearInterval(this._timer)
    this._timer = null
  }

  #poll() {
    fetch(`/runs/${this.runIdValue}/rom_downloads/${this._downloadId}`)
      .then((r) => r.json())
      .then((data) => {
        if (data.status === "ready") {
          this.#stopPolling()
          this.#succeed()
        } else if (data.status === "failed") {
          this.#stopPolling()
          this.#fail(data.error || "Generation failed.")
        }
      })
      .catch(() => {
        this.#stopPolling()
        this.#fail("Lost contact with the server.")
      })
  }

  #succeed() {
    this.#setStatus("")
    this.buttonTarget.disabled = false
    this.linkTarget.href =
      `/runs/${this.runIdValue}/rom_downloads/${this._downloadId}/download`
    this.linkTarget.classList.remove("hidden")
  }

  #fail(message) {
    this.buttonTarget.disabled = false
    this.#setStatus(`⚠️ ${message}`)
  }

  #setStatus(text) {
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("hidden", text === "")
  }
}
