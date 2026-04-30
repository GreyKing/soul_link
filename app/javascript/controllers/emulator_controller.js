// EmulatorJS bridge.
//
// EmulatorJS configures itself via `window.EJS_*` globals that loader.js
// reads when it boots. This controller's job:
//   1. Fetch any existing SRAM for this player's session.
//   2. Set the EJS_* globals (rom URL, core, pathtodata, save callbacks,
//      auto-save interval default).
//   3. On EJS_ready, register the in-game-save listener (saveSaveFiles)
//      and then write the server's SRAM into the emulator's virtual
//      filesystem so the player resumes where they left off.
//   4. Inject loader.js into the page.
//   5. When EmulatorJS fires saveSaveFiles (from the auto-save interval,
//      exit, or netplay-pause) or saveSave (manual "Save File" button),
//      PATCH the SRAM bytes back to the server.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    romUrl: String,
    saveDataUrl: String,
    csrf: String,
    core: String,
    pathtodata: String,
    cheats: { type: Array, default: [] }
  }

  static targets = ["game"]

  async connect() {
    // Server is the source of truth on load. IDBFS is a local convenience
    // cache; if both have data, we inject the server copy into MEMFS inside
    // EJS_ready so melonDS reloads from it.
    const existingSave = await this._fetchSave()

    // Set the auto-save interval default BEFORE loader.js boots. loader.js
    // reads window.EJS_defaultOptions synchronously and feeds it through
    // config.defaultOptions → menu UI's defaultOption path, which sets up
    // the internal save-save-interval setInterval. localStorage overrides
    // this for returning users who've changed it via the in-game menu.
    window.EJS_defaultOptions = { "save-save-interval": "30" }

    window.EJS_player = "#" + this.gameTarget.id
    window.EJS_gameUrl = this.romUrlValue
    window.EJS_core = this.coreValue
    window.EJS_pathtodata = this.pathtodataValue
    window.EJS_startOnLoaded = true
    window.EJS_Buttons = {}

    // EmulatorJS reads window.EJS_cheats in loader.js (assigned to
    // config.cheats), which emulator.js consumes as an array of [desc, code]
    // tuples — see public/emulatorjs/data/loader.js:102 and
    // public/emulatorjs/data/src/emulator.js:311-323. Each cheat is loaded
    // disabled (`checked: false`) and toggleable via the in-game cheat
    // menu. We honor the YAML's `enabled` flag by filtering disabled
    // entries out so they don't appear in the menu at all.
    if (this.cheatsValue.length > 0) {
      const tuples = this.cheatsValue
        .filter(c => c && c.enabled !== false && c.name && c.code)
        .map(c => [c.name, c.code])
      if (tuples.length > 0) window.EJS_cheats = tuples
    }

    // EmulatorJS fires "saveSave" with { screenshot, format, save } when the
    // user clicks the EmulatorJS UI's manual "Save File" button. The
    // presence of this handler also suppresses the default download dialog.
    // Belt-and-suspenders: the saveSaveFiles listener registered in
    // EJS_ready covers in-game saves and the auto-save interval.
    window.EJS_onSaveSave = (event) => {
      if (event && event.save) this._uploadSave(event.save)
    }

    // EJS_ready fires once after window.EJS_emulator is constructed. This
    // is the earliest safe point to register listeners on the emulator
    // instance and to write into MEMFS via gameManager.
    window.EJS_ready = () => {
      // Register the saveSaveFiles listener BEFORE injecting the existing
      // save. _injectExistingSave calls gm.loadSaveFiles(), which can race
      // with an auto-save tick; if the listener weren't already attached
      // we'd miss the first event.
      if (window.EJS_emulator) {
        window.EJS_emulator.on("saveSaveFiles", (bytes) => this._uploadSave(bytes))
      }
      if (existingSave) {
        this._injectExistingSave(existingSave)
      }
      console.log("Emulator: hooks attached", {
        hasExistingSave: !!existingSave,
        hasEmulator: !!window.EJS_emulator
      })
    }

    const script = document.createElement("script")
    script.src = this.pathtodataValue + "loader.js"
    script.id = "emulator-loader-script"
    document.body.appendChild(script)
    this._loaderScript = script
  }

  disconnect() {
    // Best-effort cleanup. EmulatorJS doesn't expose a teardown API in v4 —
    // a real navigation away from the page reloads everything anyway.
    window.EJS_player = undefined
    window.EJS_gameUrl = undefined
    window.EJS_core = undefined
    window.EJS_pathtodata = undefined
    window.EJS_startOnLoaded = undefined
    window.EJS_Buttons = undefined
    window.EJS_onSaveSave = undefined
    window.EJS_ready = undefined
    window.EJS_cheats = undefined
    window.EJS_defaultOptions = undefined
    if (this._loaderScript && this._loaderScript.parentNode) {
      this._loaderScript.parentNode.removeChild(this._loaderScript)
    }
  }

  async _fetchSave() {
    try {
      const res = await fetch(this.saveDataUrlValue, {
        method: "GET",
        headers: { "Accept": "application/octet-stream" },
        credentials: "same-origin"
      })
      if (res.status === 204) return null
      if (!res.ok) {
        console.error("Emulator: failed to load existing save:", res.status)
        return null
      }
      const buf = await res.arrayBuffer()
      return buf.byteLength > 0 ? new Uint8Array(buf) : null
    } catch (e) {
      console.error("Emulator: error fetching save:", e)
      return null
    }
  }

  _injectExistingSave(bytes) {
    try {
      const emu = window.EJS_emulator
      if (!emu || !emu.gameManager) return
      const gm = emu.gameManager
      const path = gm.getSaveFilePath()
      if (!path) return

      // Make sure the parent directories exist before writing.
      const parts = path.split("/")
      let cp = ""
      for (let i = 0; i < parts.length - 1; i++) {
        if (parts[i] === "") continue
        cp += "/" + parts[i]
        if (!gm.FS.analyzePath(cp).exists) gm.FS.mkdir(cp)
      }
      if (gm.FS.analyzePath(path).exists) gm.FS.unlink(path)
      gm.FS.writeFile(path, bytes)
      gm.loadSaveFiles()
    } catch (e) {
      console.error("Emulator: failed to inject existing save:", e)
    }
  }

  async _uploadSave(saveBytes) {
    // Skip null / 0-byte payloads. getSaveFile(false) returns null pre-first-
    // save, and an empty SRAM PATCH would clobber an existing real save on
    // the server.
    if (!saveBytes || saveBytes.byteLength === 0) return
    const blob = saveBytes instanceof Uint8Array
      ? saveBytes
      : new Uint8Array(saveBytes)
    try {
      const res = await fetch(this.saveDataUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/octet-stream",
          "X-CSRF-Token": this.csrfValue
        },
        credentials: "same-origin",
        body: blob
      })
      if (!res.ok) {
        console.error("Emulator: failed to upload save:", res.status)
      }
    } catch (e) {
      console.error("Emulator: error uploading save:", e)
    }
  }
}
