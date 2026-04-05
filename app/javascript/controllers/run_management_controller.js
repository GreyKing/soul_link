import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "currentRunPanel", "noRunPanel", "historyList",
    "runNumber", "gymsDefeated", "caughtCount", "deadCount", "startedAt",
    "setupDiscordButton"
  ]
  static values = {
    guildId: String,
    userId: String
  }

  connect() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "RunChannel", guild_id: this.guildIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
    this.state = null
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  handleMessage(data) {
    if (data.error) {
      console.error("Run error:", data.error)
      return
    }
    if (data.type === "state_update") {
      this.state = data.state
      this.render()
    }
  }

  // ── User Actions ──

  startRun() {
    if (!confirm("Start a new run? This will end any active run.")) return
    this.subscription.perform("start_run")
  }

  endRun() {
    if (!confirm("End the current run? All data will be preserved.")) return
    this.subscription.perform("end_run")
  }

  setupDiscord() {
    this.setupDiscordButtonTarget.disabled = true
    this.setupDiscordButtonTarget.textContent = "Setting up..."
    this.subscription.perform("setup_discord")
  }

  // ── Rendering ──

  render() {
    if (!this.state) return

    const { current_run, past_runs } = this.state

    if (current_run) {
      this.currentRunPanelTarget.classList.remove("hidden")
      this.noRunPanelTarget.classList.add("hidden")

      this.runNumberTarget.textContent = `#${current_run.run_number}`
      this.gymsDefeatedTarget.textContent = `${current_run.gyms_defeated}/8`
      this.caughtCountTarget.textContent = current_run.caught_count
      this.deadCountTarget.textContent = current_run.dead_count

      if (current_run.started_at) {
        const date = new Date(current_run.started_at)
        this.startedAtTarget.textContent = date.toLocaleDateString("en-US", {
          month: "short", day: "numeric", year: "numeric"
        })
      }

      if (current_run.has_discord_channels) {
        this.setupDiscordButtonTarget.classList.add("hidden")
      } else {
        this.setupDiscordButtonTarget.classList.remove("hidden")
        this.setupDiscordButtonTarget.disabled = false
        this.setupDiscordButtonTarget.textContent = "Setup Discord Channels"
      }
    } else {
      this.currentRunPanelTarget.classList.add("hidden")
      this.noRunPanelTarget.classList.remove("hidden")
    }

    this.renderHistory(past_runs || [])
  }

  renderHistory(pastRuns) {
    if (pastRuns.length === 0) {
      this.historyListTarget.innerHTML = `<p class="text-gray-500 text-sm">No previous runs.</p>`
      return
    }

    this.historyListTarget.innerHTML = pastRuns.map(run => {
      const startDate = run.started_at ? new Date(run.started_at).toLocaleDateString("en-US", { month: "short", day: "numeric" }) : ""
      const endDate = run.ended_at ? new Date(run.ended_at).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : ""

      return `
        <div class="bg-gray-800/30 rounded-lg border border-gray-700/50 p-4 opacity-60">
          <div class="flex items-center justify-between">
            <div>
              <span class="text-white font-medium">Run #${run.run_number}</span>
              <span class="text-gray-500 text-sm ml-3">${startDate} &mdash; ${endDate}</span>
            </div>
            <div class="flex items-center gap-4 text-sm">
              <span class="text-gray-400">${run.gyms_defeated}/8 gyms</span>
              <span class="text-green-400">${run.caught_count} caught</span>
              <span class="text-red-400">${run.dead_count} dead</span>
            </div>
          </div>
        </div>
      `
    }).join("")
  }
}
