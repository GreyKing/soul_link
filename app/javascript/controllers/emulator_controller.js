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
    firmwareUrl: String,
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

    // Set core / save defaults BEFORE loader.js boots. loader.js reads
    // window.EJS_defaultOptions synchronously and feeds it through
    // config.defaultOptions, which becomes the core's option file.
    // localStorage overrides these for returning users who've changed
    // them via the in-game menu.
    //
    // - save-save-interval = "0": auto-flush DISABLED. The 30s tick
    //   calls melonDS's cmd_savefiles WASM export mid-frame, which races
    //   with Pokemon's own SRAM writes during intro animations (name
    //   input, gender selection, receive-starter cutscene) and corrupts
    //   the running emulation — observed as a hang at starter selection
    //   on Pokemon Platinum. melonDS doesn't promise thread-safety
    //   between cmd_savefiles and the running CPU emulation. Players
    //   back up to the server by clicking the EmulatorJS "Save File"
    //   button after an in-game save (fires saveSave → EJS_onSaveSave).
    // - melonds_boot_mode = "direct": skip the DS firmware boot UI and
    //   jump straight into the ROM. REQUIRED when firmware is dumped from
    //   a DSi or 3DS — those firmwares aren't bootable
    //   (https://docs.libretro.com/library/melonds_ds/), and "native"
    //   mode tries to boot the firmware UI and crashes the game later.
    //   With direct boot, the firmware bytes are still loaded so Pokemon's
    //   WiFi calibration check passes.
    // - melonds_boot_directly: same intent for the older melonDS 2021
    //   libretro core. Setting both is harmless; whichever core
    //   EmulatorJS resolves will pick up its own key.
    window.EJS_defaultOptions = {
      "save-save-interval": "0",
      "melonds_boot_mode": "direct",
      "melonds_boot_directly": "enabled"
    }

    window.EJS_player = "#" + this.gameTarget.id
    window.EJS_gameUrl = this.romUrlValue
    window.EJS_core = this.coreValue
    window.EJS_pathtodata = this.pathtodataValue
    window.EJS_startOnLoaded = true
    window.EJS_Buttons = {}

    // Real DS firmware ZIP — fixes Pokemon's "communication error" on save
    // load by giving melonDS valid WiFi calibration bytes (its auto-
    // generated firmware leaves them FF-padded, which Pokemon rejects).
    // EmulatorJS extracts the ZIP and reads bios7.bin / bios9.bin /
    // firmware.bin from the BIOS/system folder via this URL.
    if (this.firmwareUrlValue) window.EJS_biosUrl = this.firmwareUrlValue

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
    // user clicks the EmulatorJS UI's manual "Save File" button. The mere
    // presence of this handler suppresses the default download dialog —
    // so we have to do the download ourselves on top of the server PATCH.
    // Belt-and-suspenders: the saveSaveFiles listener registered in
    // EJS_ready covers in-game saves and the auto-save interval.
    window.EJS_onSaveSave = (event) => {
      if (!event || !event.save) return
      this._uploadSave(event.save)
      this._triggerDownload(event.save, event.format)
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
    window.EJS_biosUrl = undefined
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

  // Triggers a browser download of the SRAM bytes. Called only from the
  // manual "Save File" button path — the auto-save tick should not spam
  // the user's Downloads folder every 30 seconds.
  _triggerDownload(saveBytes, format) {
    if (!saveBytes || saveBytes.byteLength === 0) return
    const bytes = saveBytes instanceof Uint8Array ? saveBytes : new Uint8Array(saveBytes)
    const blob = new Blob([bytes], { type: "application/octet-stream" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = `pokemon-platinum-save.${format || "sav"}`
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
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
