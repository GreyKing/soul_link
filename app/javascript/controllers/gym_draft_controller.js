import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = [
    "phaseLabel", "phaseInfo", "errorBanner",
    "lobbyPanel", "readyGrid", "readyButton",
    "votingPanel", "voteGrid", "voteStatus",
    "draftingPanel", "teamSlots", "turnIndicator", "myPokemonGrid",
    "nominatingPanel", "nomTeamSlots", "nomStatus", "nomOrderStrip",
    "nomGraceCountdown", "nomSkipButton", "nomCandidatesList", "nomPokemonGrid",
    "completePanel", "finalTeamSlots",
    "skipButton",
    "coinFlipModal", "coinFlipMessage", "coinFlipCoin", "coinFlipResult"
  ]
  static values = {
    draftId: Number,
    userId: String,
    players: Array,
    playerGroups: Object,
    playerAvatars: Object
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
    this.graceTickTimer = null
    this.coinFlipShownFor = null
    this.coinFlipTimers = []
  }

  disconnect() {
    this.clearSkipTimer()
    this.clearGraceTick()
    this.clearCoinFlipTimers()
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  handleMessage(data) {
    if (data.error) {
      console.error("Draft error:", data.error)
      this.showError(data.error)
      return
    }
    if (data.type === "state_update") {
      this.state = data.state
      this.render()
    }
  }

  showError(message) {
    if (!this.hasErrorBannerTarget) {
      window.alert(`Draft error: ${message}`)
      return
    }
    this.errorBannerTarget.textContent = message
    this.errorBannerTarget.hidden = false
    if (this._errorTimer) clearTimeout(this._errorTimer)
    this._errorTimer = setTimeout(() => {
      this.errorBannerTarget.hidden = true
    }, 8000)
  }

  // ── User Actions ──

  ready() {
    this.subscription.perform("ready")
    this.readyButtonTarget.disabled = true
    this.readyButtonTarget.textContent = "Waiting..."
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

  // Step 14: unified action — server picks new-vs-endorse based on
  // whether the group_id is already a candidate.
  nominateOrEndorse(event) {
    const groupId = parseInt(event.currentTarget.dataset.groupId)
    this.subscription.perform("nominate", { group_id: groupId })
    this.disablePokemonCards(this.nomPokemonGridTarget)
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

    // Clear timers — drafting/nominating renderers will restart what they need.
    if (status !== "drafting") {
      this.clearSkipTimer()
    }
    if (status !== "nominating") {
      this.clearGraceTick()
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

    // Coin flip is a complete-phase concern but the modal lives outside
    // the panel toggles so it can overlay the page during the reveal.
    this.maybeShowCoinFlip()
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
        statusEl.style.color = isReady ? "var(--accent)" : "var(--l1)"
      }
    })

    const myReady = readyPlayers.includes(this.userIdValue)
    if (myReady) {
      this.readyButtonTarget.disabled = true
      this.readyButtonTarget.textContent = "Waiting..."
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

    this.phaseInfoTarget.textContent = `Round ${this.state.picks.length + 1}/4`

    // Render my pokemon as pickable cards
    this.renderPokemonGrid(this.myPokemonGridTarget, isMyTurn, "pick")

    this.startSkipTimer()
  }

  renderNominating() {
    this.fillTeamSlots(this.nomTeamSlotsTarget, this.state.picks)

    const currentNominatorId = this.state.current_nominator_id
    const isMyTurnToNominate = String(currentNominatorId) === this.userIdValue
    const currentPlayer = this.findPlayer(currentNominatorId)

    const remaining = this.state.nomination_picks_remaining ?? 0
    this.phaseInfoTarget.textContent = `${remaining} pick${remaining === 1 ? "" : "s"} left`
    this.nomStatusTarget.textContent = isMyTurnToNominate
      ? "Your turn — pick a pokemon to nominate or endorse."
      : `Waiting for ${currentPlayer?.display_name || "..."} to pick...`

    this.renderNomOrderStrip()
    this.renderCandidates()
    this.renderNomPokemonGrid(isMyTurnToNominate)
    this.renderNomGraceCountdown()
  }

  renderComplete() {
    this.fillTeamSlots(this.finalTeamSlotsTarget, this.state.picks)
    this.phaseInfoTarget.textContent = "Team drafted!"
  }

  // ── Nominating helpers (Step 14) ──

  renderNomOrderStrip() {
    const order = this.state.pick_order || []
    const made = (this.state.candidates || []).flatMap(c => c.voters || []).map(String)
    const currentNomId = String(this.state.current_nominator_id)

    this.nomOrderStripTarget.replaceChildren()
    const wrap = document.createElement("div")
    wrap.style.display = "flex"
    wrap.style.justifyContent = "center"
    wrap.style.gap = "8px"
    wrap.style.flexWrap = "wrap"

    order.forEach(uid => {
      const pid = String(uid)
      const player = this.findPlayer(pid)
      const hasPicked = made.includes(pid)
      const isCurrent = pid === currentNomId

      const chip = document.createElement("div")
      chip.style.padding = "6px 10px"
      chip.style.fontSize = "10px"
      chip.style.border = "2px solid var(--d1)"
      chip.style.background = hasPicked ? "var(--d2)" : "var(--l1)"
      chip.style.color = hasPicked ? "var(--l2)" : "var(--d1)"
      chip.style.fontFamily = "'Press Start 2P', monospace"
      if (isCurrent) {
        chip.style.borderColor = "var(--accent)"
        chip.style.boxShadow = "0 0 0 2px var(--accent)"
      }
      const prefix = hasPicked ? "✓ " : (isCurrent ? "▶ " : "")
      chip.textContent = `${prefix}${player?.display_name || pid}`
      wrap.appendChild(chip)
    })

    this.nomOrderStripTarget.appendChild(wrap)
  }

  renderCandidates() {
    const candidates = this.state.candidates || []
    const list = this.nomCandidatesListTarget
    list.replaceChildren()

    if (candidates.length === 0) {
      const empty = document.createElement("div")
      empty.style.fontSize = "10px"
      empty.style.color = "var(--d2)"
      empty.textContent = "No nominations yet."
      list.appendChild(empty)
      return
    }

    const maxCount = Math.max(...candidates.map(c => (c.voters || []).length))

    candidates.forEach(cand => {
      const group = this.findGroupById(cand.group_id)
      const card = document.createElement("div")
      card.className = "gb-candidate-card"
      const voters = cand.voters || []
      if (voters.length === maxCount) {
        card.classList.add("gb-candidate-card--leading")
      }

      const name = document.createElement("div")
      name.className = "gb-candidate-card__name"
      name.textContent = group?.nickname || `#${cand.group_id}`
      card.appendChild(name)

      // Each linked pokemon (one per player) on its own line — mirrors the
      // gym-result snapshot rendering at _gyms_content.html.erb:81.
      // Showing only `pokemon[0].species` was misleading: AR ordering of
      // the soul_link_pokemon association is undefined, so the single
      // species rendered was effectively "whichever player happened to be
      // saved first," which read as "just my pokemon" to viewers.
      const pokemon = group?.pokemon || []
      if (pokemon.length > 0) {
        const speciesContainer = document.createElement("div")
        speciesContainer.className = "gb-candidate-card__species"
        pokemon.forEach(p => {
          const player = this.findPlayer(p.discord_user_id)
          const label = player?.display_name || "?"
          const line = document.createElement("div")
          line.textContent = `${label}: ${p.species || "?"}`
          speciesContainer.appendChild(line)
        })
        card.appendChild(speciesContainer)
      }

      const row = document.createElement("div")
      row.className = "gb-candidate-card__row"

      const pile = document.createElement("div")
      pile.className = "gb-avatar-pile"
      voters.forEach(uid => pile.appendChild(this.buildAvatar(uid)))
      row.appendChild(pile)

      const count = document.createElement("div")
      count.className = "gb-candidate-card__count"
      count.textContent = `★ ${voters.length}`
      row.appendChild(count)

      card.appendChild(row)
      list.appendChild(card)
    })
  }

  renderNomPokemonGrid(canPick) {
    const candidateGroupIds = new Set((this.state.candidates || []).map(c => c.group_id))
    this.renderPokemonGrid(this.nomPokemonGridTarget, canPick, "nominate", {
      labelForGroup: (group) => candidateGroupIds.has(group.id) ? "ENDORSE" : "NOMINATE"
    })
  }

  renderNomGraceCountdown() {
    this.clearGraceTick()
    const ts = this.state.current_turn_started_at
    if (!ts) {
      this.nomGraceCountdownTarget.textContent = ""
      this.hideNomSkipButton()
      return
    }

    const tick = () => {
      const startedAt = Date.parse(ts)
      const elapsed = Math.floor((Date.now() - startedAt) / 1000)
      const remaining = 60 - elapsed
      const isMyTurn = String(this.state.current_nominator_id) === this.userIdValue

      if (remaining > 0) {
        this.nomGraceCountdownTarget.textContent = `(grace ${remaining}s)`
        // Only the current nominator can skip during grace.
        if (isMyTurn) {
          this.showNomSkipButton(`SKIP MY TURN (${remaining}s)`)
        } else {
          this.hideNomSkipButton()
        }
      } else {
        this.nomGraceCountdownTarget.textContent = "(skip available)"
        // After grace, anyone may skip.
        this.showNomSkipButton(isMyTurn ? "SKIP MY TURN" : "SKIP STALLED TURN")
      }
    }

    tick()
    this.graceTickTimer = setInterval(tick, 1000)
  }

  showNomSkipButton(label) {
    const target = this.nomSkipButtonTarget
    target.classList.remove("hidden")
    if (target.dataset.currentLabel !== label || target.children.length === 0) {
      target.replaceChildren()
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "gb-btn gb-btn-sm"
      btn.textContent = label
      btn.addEventListener("click", () => {
        this.subscription.perform("skip")
        btn.disabled = true
        btn.textContent = "Skipping..."
      })
      target.appendChild(btn)
      target.dataset.currentLabel = label
    }
  }

  hideNomSkipButton() {
    this.nomSkipButtonTarget.classList.add("hidden")
    this.nomSkipButtonTarget.replaceChildren()
    delete this.nomSkipButtonTarget.dataset.currentLabel
  }

  clearGraceTick() {
    if (this.graceTickTimer) {
      clearInterval(this.graceTickTimer)
      this.graceTickTimer = null
    }
    this.hideNomSkipButton()
  }

  // ── Coin-flip modal (Step 14) ──

  maybeShowCoinFlip() {
    if (!this.hasCoinFlipModalTarget) return
    const tb = this.state?.tiebreak
    const status = this.state?.status

    // Modal only shows for completed drafts that recorded a tiebreak.
    if (status !== "complete" || !tb) {
      this.coinFlipModalTarget.classList.add("hidden")
      return
    }

    // Dedupe: render() fires on every state update, the modal must
    // animate exactly once per resolution. Key on the JSON shape so a
    // second tiebreak (impossible today, but defensive) would re-fire.
    const key = JSON.stringify(tb)
    if (this.coinFlipShownFor === key) return
    this.coinFlipShownFor = key

    this.runCoinFlipAnimation(tb)
  }

  runCoinFlipAnimation(tiebreak) {
    this.clearCoinFlipTimers()
    const modal = this.coinFlipModalTarget
    const message = this.coinFlipMessageTarget
    const coin = this.coinFlipCoinTarget
    const result = this.coinFlipResultTarget

    const tied = tiebreak.tied_group_ids || []
    const winners = (tiebreak.winners || []).map(id => {
      const g = this.findGroupById(id)
      return g?.nickname || `#${id}`
    })

    if (tiebreak.type === "n_way") {
      message.textContent = `All ${tied.length} picks were unique. The coin chooses ${winners.length}.`
    } else {
      message.textContent = `Slot 6 was tied between ${tied.length} candidates.`
    }

    // Hide stale result, show the modal, restart the keyframe.
    result.classList.add("hidden")
    result.textContent = ""
    modal.classList.remove("hidden")
    coin.classList.remove("tcg-coin--flipping")
    void coin.offsetWidth
    coin.classList.add("tcg-coin--flipping")

    this.coinFlipTimers.push(setTimeout(() => {
      result.textContent = `Winner${winners.length === 1 ? "" : "s"}: ${winners.join(" + ")}`
      result.classList.remove("hidden")
    }, 1900))

    this.coinFlipTimers.push(setTimeout(() => {
      modal.classList.add("hidden")
      coin.classList.remove("tcg-coin--flipping")
    }, 4000))
  }

  clearCoinFlipTimers() {
    if (this.coinFlipTimers) {
      this.coinFlipTimers.forEach(t => clearTimeout(t))
    }
    this.coinFlipTimers = []
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

  renderPokemonGrid(container, interactive, actionType, opts = {}) {
    const myUid = this.userIdValue
    const allGroups = this.playerGroupsValue[myUid] || []
    const pickedGroupIds = (this.state.picks || []).map(p => p.group_id)
    const action = actionType === "pick" ? "click->gym-draft#pickPokemon" : "click->gym-draft#nominateOrEndorse"

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

        if (opts.labelForGroup) {
          const tag = document.createElement("div")
          tag.className = "text-[10px]"
          tag.style.color = "var(--accent)"
          tag.style.marginTop = "4px"
          tag.textContent = opts.labelForGroup(group)
          card.appendChild(tag)
        }
      }

      container.appendChild(card)
    })
  }

  buildAvatar(uid) {
    const pid = String(uid)
    const url = (this.playerAvatarsValue || {})[pid]
    if (url) {
      const img = document.createElement("img")
      img.src = url
      img.alt = ""
      img.className = "gb-avatar gb-avatar--24"
      return img
    }
    const span = document.createElement("span")
    const player = this.findPlayer(pid)
    const name = player?.display_name || pid
    const initial = (name[0] || "?").toUpperCase()
    const colorIndex = (parseInt(pid, 10) || 0) % 4
    span.className = `gb-avatar gb-avatar--24 gb-avatar--initial gb-avatar--c${colorIndex}`
    span.textContent = initial
    span.title = name
    return span
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

  startSkipTimer() {
    // Drafting-only legacy skip surface — kept simple, 30s passive
    // delay then a button. The nominating-phase skip is driven by the
    // grace countdown render.
    this.clearSkipTimer()
    const targetEl = this.skipButtonTargets.find(el => this.draftingPanelTarget.contains(el))
    if (!targetEl) return

    this.skipTurnTimer = setTimeout(() => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "gb-btn gb-btn-sm"
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
