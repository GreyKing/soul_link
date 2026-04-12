import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "phaseLabel", "phaseInfo",
    "lobbyPanel", "readyGrid", "readyButton",
    "votingPanel", "voteGrid", "voteStatus",
    "draftingPanel", "teamSlots", "turnIndicator", "myPokemonGrid",
    "nominatingPanel", "nomTeamSlots", "nomStatus", "nomVoteArea", "nomVotePrompt", "nomPokemonGrid",
    "completePanel", "finalTeamSlots",
    "skipButton"
  ]
  static values = {
    draftId: Number,
    userId: String,
    players: Array,
    playerGroups: Object
  }

  connect() {
    this.subscription = createConsumer().subscriptions.create(
      { channel: "GymDraftChannel", draft_id: this.draftIdValue },
      {
        received: (data) => this.handleMessage(data)
      }
    )
    this.state = null
    this.skipTurnTimer = null
  }

  disconnect() {
    this.clearSkipTimer()
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  handleMessage(data) {
    if (data.error) {
      console.error("Draft error:", data.error)
      return
    }
    if (data.type === "state_update") {
      this.state = data.state
      this.render()
    }
  }

  // ── User Actions ──

  ready() {
    this.subscription.perform("ready")
    this.readyButtonTarget.disabled = true
    this.readyButtonTarget.textContent = "Waiting..."
    this.readyButtonTarget.classList.replace("bg-green-600", "bg-gray-600")
  }

  vote(event) {
    const votedFor = event.currentTarget.dataset.voteFor
    this.subscription.perform("vote", { voted_for: votedFor })
    // Disable all vote buttons
    this.voteGridTarget.querySelectorAll("button").forEach(btn => {
      btn.disabled = true
      btn.classList.add("opacity-50")
    })
    event.currentTarget.classList.add("border-indigo-500", "bg-indigo-950/30")
  }

  pickPokemon(event) {
    const groupId = parseInt(event.currentTarget.dataset.groupId)
    this.subscription.perform("pick", { group_id: groupId })
    this.disablePokemonCards(this.myPokemonGridTarget)
  }

  nominatePokemon(event) {
    const groupId = parseInt(event.currentTarget.dataset.groupId)
    this.subscription.perform("nominate", { group_id: groupId })
    this.disablePokemonCards(this.nomPokemonGridTarget)
  }

  approveNomination() {
    this.subscription.perform("vote_nomination", { approve: true })
    this.nomVoteAreaTarget.querySelectorAll("button").forEach(btn => { btn.disabled = true })
  }

  rejectNomination() {
    this.subscription.perform("vote_nomination", { approve: false })
    this.nomVoteAreaTarget.querySelectorAll("button").forEach(btn => { btn.disabled = true })
  }

  disablePokemonCards(grid) {
    grid.querySelectorAll("[data-group-id]").forEach(card => {
      card.style.pointerEvents = "none"
      card.classList.add("opacity-50")
    })
  }

  // ── Rendering ──

  render() {
    if (!this.state) return

    const { status } = this.state
    this.phaseLabelTarget.textContent = this.phaseDisplayName(status)

    // Clear skip timer — drafting/nominating renderers will restart it
    if (status !== "drafting" && status !== "nominating") {
      this.clearSkipTimer()
    }

    // Show/hide panels
    this.lobbyPanelTarget.classList.toggle("hidden", status !== "lobby")
    this.votingPanelTarget.classList.toggle("hidden", status !== "voting")
    this.draftingPanelTarget.classList.toggle("hidden", status !== "drafting")
    this.nominatingPanelTarget.classList.toggle("hidden", status !== "nominating")
    this.completePanelTarget.classList.toggle("hidden", status !== "complete")

    switch (status) {
      case "lobby": this.renderLobby(); break
      case "voting": this.renderVoting(); break
      case "drafting": this.renderDrafting(); break
      case "nominating": this.renderNominating(); break
      case "complete": this.renderComplete(); break
    }
  }

  renderLobby() {
    const readyPlayers = (this.state.ready_players || []).map(String)
    const cards = this.readyGridTarget.querySelectorAll("[data-player-id]")
    cards.forEach(card => {
      const pid = card.dataset.playerId
      const isReady = readyPlayers.includes(pid)
      const statusEl = card.querySelector(".ready-status")
      if (statusEl) {
        statusEl.textContent = isReady ? "Ready!" : "Not ready"
        statusEl.className = `text-xs mt-1 ready-status ${isReady ? "text-green-400" : "text-gray-500"}`
      }
      card.classList.toggle("border-green-600", isReady)
      card.classList.toggle("border-gray-700", !isReady)
    })

    const myReady = readyPlayers.includes(this.userIdValue)
    if (myReady) {
      this.readyButtonTarget.disabled = true
      this.readyButtonTarget.textContent = "Waiting..."
      this.readyButtonTarget.classList.replace("bg-green-600", "bg-gray-600")
    }

    this.phaseInfoTarget.textContent = `${readyPlayers.length}/${(this.state.player_ids || []).length} ready`
  }

  renderVoting() {
    const votes = this.state.first_pick_votes || {}
    const voteCount = Object.keys(votes).length
    const total = (this.state.player_ids || []).length
    this.voteStatusTarget.textContent = `${voteCount}/${total} votes cast`

    const myVoted = votes[this.userIdValue]
    if (myVoted) {
      this.voteGridTarget.querySelectorAll("button").forEach(btn => {
        btn.disabled = true
        btn.classList.add("opacity-50")
        if (btn.dataset.voteFor === String(myVoted)) {
          btn.classList.remove("opacity-50")
          btn.classList.add("border-indigo-500", "bg-indigo-950/30")
        }
      })
    }

    this.phaseInfoTarget.textContent = `${voteCount}/${total} votes`
  }

  renderDrafting() {
    this.fillTeamSlots(this.teamSlotsTarget, this.state.picks)

    const currentId = String(this.state.current_drafter_id)
    const currentPlayer = this.findPlayer(currentId)
    const isMyTurn = currentId === this.userIdValue

    this.turnIndicatorTarget.textContent = isMyTurn
      ? "It's your turn! Pick a pokemon."
      : `Waiting for ${currentPlayer?.display_name || "..."} to pick...`

    this.phaseInfoTarget.textContent = `Round ${this.state.picks.length + 1}/6`

    // Render my pokemon as pickable cards
    this.renderPokemonGrid(this.myPokemonGridTarget, isMyTurn, "pick")

    this.startSkipTimer("drafting")
  }

  renderNominating() {
    this.fillTeamSlots(this.nomTeamSlotsTarget, this.state.picks)

    const nomination = this.state.current_nomination
    const slotsRemaining = 6 - this.state.picks.length

    this.phaseInfoTarget.textContent = `${slotsRemaining} slot${slotsRemaining > 1 ? "s" : ""} remaining`

    if (nomination) {
      const nominator = this.findPlayer(nomination.nominator_id)
      const group = this.findGroupById(nomination.group_id)
      const groupName = group ? group.nickname : `Group #${nomination.group_id}`

      this.nomStatusTarget.textContent = `${nominator?.display_name} nominated "${groupName}"`

      // Show vote buttons for non-nominators
      const isNominator = String(nomination.nominator_id) === this.userIdValue
      const hasVoted = nomination.votes && nomination.votes[this.userIdValue] !== undefined

      if (!isNominator && !hasVoted) {
        this.nomVoteAreaTarget.classList.remove("hidden")
        this.nomVoteAreaTarget.classList.remove("opacity-50")
        this.nomVotePromptTarget.textContent = `Do you agree with "${groupName}"?`
      } else {
        this.nomVoteAreaTarget.classList.add("hidden")
      }
    } else {
      const currentNominatorId = this.state.pick_order
        ? this.state.pick_order[this.state.current_player_index % this.state.pick_order.length]
        : null
      const isMyTurnToNominate = String(currentNominatorId) === this.userIdValue
      const currentNominator = this.findPlayer(currentNominatorId)
      this.nomStatusTarget.textContent = isMyTurnToNominate
        ? "Your turn to nominate a pokemon!"
        : `Waiting for ${currentNominator?.display_name || "..."} to nominate...`
      this.nomVoteAreaTarget.classList.add("hidden")
    }

    // Render pokemon grid for nomination
    const currentNominatorId = this.state.pick_order
      ? this.state.pick_order[this.state.current_player_index % this.state.pick_order.length]
      : null
    const isMyTurnToNominate = String(currentNominatorId) === this.userIdValue
    const canNominate = !nomination && isMyTurnToNominate
    this.renderPokemonGrid(this.nomPokemonGridTarget, canNominate, "nominate")

    this.startSkipTimer("nominating")
  }

  renderComplete() {
    this.fillTeamSlots(this.finalTeamSlotsTarget, this.state.picks)
    this.phaseInfoTarget.textContent = "Team drafted!"
  }

  // ── Helpers ──

  fillTeamSlots(container, picks) {
    const slots = container.querySelectorAll("[data-slot-index]")
    slots.forEach((slot, idx) => {
      const pick = picks[idx]
      slot.replaceChildren()
      if (pick) {
        const group = this.findGroupById(pick.group_id)
        const picker = this.findPlayer(pick.picked_by)
        if (group) {
          const nameDiv = document.createElement("div")
          nameDiv.className = "text-xs font-medium text-white"
          nameDiv.textContent = group.nickname

          const pickerDiv = document.createElement("div")
          pickerDiv.className = "text-[10px] text-gray-500"
          pickerDiv.textContent = picker?.display_name || ""

          slot.append(nameDiv, pickerDiv)
          slot.classList.remove("border-dashed", "border-gray-600")
          slot.classList.add("border-solid", "border-indigo-600", "bg-indigo-950/30")
        }
      } else {
        const numSpan = document.createElement("span")
        numSpan.className = "text-xs text-gray-600"
        numSpan.textContent = `#${idx + 1}`
        slot.appendChild(numSpan)
        slot.classList.add("border-dashed", "border-gray-600")
        slot.classList.remove("border-solid", "border-indigo-600", "bg-indigo-950/30")
      }
    })
  }

  renderPokemonGrid(container, interactive, actionType) {
    const myUid = this.userIdValue
    const allGroups = this.playerGroupsValue[myUid] || []
    const pickedGroupIds = (this.state.picks || []).map(p => p.group_id)
    const action = actionType === "pick" ? "click->gym-draft#pickPokemon" : "click->gym-draft#nominatePokemon"

    container.replaceChildren()

    allGroups.forEach(group => {
      const isPicked = pickedGroupIds.includes(group.id)
      const myPokemon = group.pokemon.find(p => String(p.discord_user_id) === myUid)
      const species = myPokemon ? myPokemon.species : "?"

      const card = document.createElement("div")
      card.className = isPicked
        ? "bg-gray-900/30 rounded-lg border border-gray-700/30 p-3 text-center opacity-30"
        : `bg-gray-900/50 rounded-lg border border-gray-700 p-3 text-center transition ${interactive ? "cursor-pointer hover:border-indigo-500 hover:bg-indigo-950/30" : "opacity-50"}`

      if (isPicked) {
        const nameDiv = document.createElement("div")
        nameDiv.className = "text-sm text-gray-500"
        nameDiv.textContent = group.nickname

        const speciesDiv = document.createElement("div")
        speciesDiv.className = "text-xs text-gray-600"
        speciesDiv.textContent = species

        const pickedDiv = document.createElement("div")
        pickedDiv.className = "text-[10px] text-gray-600"
        pickedDiv.textContent = "Picked"

        card.append(nameDiv, speciesDiv, pickedDiv)
      } else {
        card.dataset.groupId = group.id
        if (interactive) {
          card.dataset.action = action
        }

        const nameDiv = document.createElement("div")
        nameDiv.className = "text-sm font-medium text-white"
        nameDiv.textContent = group.nickname

        const speciesDiv = document.createElement("div")
        speciesDiv.className = "text-xs text-indigo-300"
        speciesDiv.textContent = species

        const locationDiv = document.createElement("div")
        locationDiv.className = "text-[10px] text-gray-500"
        locationDiv.textContent = group.location

        card.append(nameDiv, speciesDiv, locationDiv)
      }

      container.appendChild(card)
    })
  }

  clearSkipTimer() {
    if (this.skipTurnTimer) {
      clearTimeout(this.skipTurnTimer)
      this.skipTurnTimer = null
    }
    this.skipButtonTargets.forEach(el => {
      el.classList.add("hidden")
      el.replaceChildren()
    })
  }

  startSkipTimer(phase) {
    this.clearSkipTimer()
    const targetEl = phase === "drafting"
      ? this.skipButtonTargets.find(el => this.draftingPanelTarget.contains(el))
      : this.skipButtonTargets.find(el => this.nominatingPanelTarget.contains(el))

    if (!targetEl) return

    this.skipTurnTimer = setTimeout(() => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "gb-btn-danger gb-btn-sm"
      btn.textContent = "SKIP TURN"
      btn.addEventListener("click", () => {
        this.subscription.perform("skip")
        btn.disabled = true
        btn.textContent = "Skipping..."
      })
      targetEl.replaceChildren(btn)
      targetEl.classList.remove("hidden")
    }, 30000)
  }

  findPlayer(id) {
    return this.playersValue.find(p => String(p.discord_user_id) === String(id))
  }

  findGroupById(groupId) {
    const allGroups = Object.values(this.playerGroupsValue).flat()
    return allGroups.find(g => g.id === groupId)
  }

  phaseDisplayName(status) {
    const names = {
      lobby: "Lobby",
      voting: "Voting",
      drafting: "Drafting",
      nominating: "Nominations",
      complete: "Complete"
    }
    return names[status] || status
  }
}
