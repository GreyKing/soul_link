// EmulatorJS bridge.
//
// EmulatorJS configures itself via `window.EJS_*` globals that loader.js
// reads when it boots. This controller's job:
//   1. Fetch any existing SRAM for this player's session.
//   2. Set the EJS_* globals (rom URL, core, pathtodata, save callback).
//   3. On EJS_ready, write the existing SRAM into the emulator's virtual
//      filesystem so the player resumes where they left off.
//   4. Inject loader.js into the page.
//   5. When EmulatorJS fires saveSave (from the in-game / button save),
//      PATCH the SRAM bytes back to the server.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    romUrl: String,
    saveDataUrl: String,
    csrf: String,
    core: String,
    pathtodata: String
  }

  static targets = ["game"]

  async connect() {
    // Pull any existing save before EmulatorJS boots so we can hand it
    // straight to the in-emulator FS once the core is ready.
    const existingSave = await this._fetchSave()

    window.EJS_player = "#" + this.gameTarget.id
    window.EJS_gameUrl = this.romUrlValue
    window.EJS_core = this.coreValue
    window.EJS_pathtodata = this.pathtodataValue
    window.EJS_startOnLoaded = true
    window.EJS_Buttons = {}

    // EmulatorJS fires "saveSave" with { screenshot, format, save }
    // whenever the player triggers an SRAM save (the in-game Save menu
    // writes to SRAM, then the user hits the "Save File" button in the
    // EmulatorJS UI). The presence of this handler suppresses the default
    // download dialog.
    window.EJS_onSaveSave = (event) => {
      if (event && event.save) this._uploadSave(event.save)
    }

    // EJS_ready fires once the core is initialized. That's our chance to
    // inject the previous SRAM into the in-emulator filesystem.
    if (existingSave) {
      window.EJS_ready = () => this._injectExistingSave(existingSave)
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
