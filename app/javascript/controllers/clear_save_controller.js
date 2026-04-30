// Player-initiated "wipe my save" button. Sends DELETE to the server,
// then deletes the local IndexedDB database that backs EmulatorJS's
// /data/saves IDBFS mount, then reloads the page so the emulator boots
// from a clean state.
//
// IDB serializes operations per-database, so a "blocked" deletion (the
// emulator's IDBFS connection is holding the DB open) is queued and
// completes the moment the page reload tears the connection down — no
// race with the next page's IDBFS mount.
import { Controller } from "@hotwired/stimulus"

const CONFIRM_MESSAGE = "Permanently delete your save data? This cannot be undone."
const IDBFS_DB_NAME = "/data/saves"

export default class extends Controller {
  static values = { url: String, csrf: String }

  async clear(event) {
    event.preventDefault()
    if (!window.confirm(CONFIRM_MESSAGE)) return

    try {
      const res = await fetch(this.urlValue, {
        method: "DELETE",
        headers: { "X-CSRF-Token": this.csrfValue },
        credentials: "same-origin"
      })
      if (!res.ok) {
        console.error("ClearSave: server DELETE failed:", res.status)
        window.alert("Could not clear save data on the server. Try again or contact the run creator.")
        return
      }
    } catch (e) {
      console.error("ClearSave: network error:", e)
      window.alert("Could not reach the server. Check your connection and try again.")
      return
    }

    await new Promise((resolve) => {
      const req = indexedDB.deleteDatabase(IDBFS_DB_NAME)
      req.onsuccess = () => resolve()
      req.onerror   = () => resolve()
      req.onblocked = () => resolve()
    })

    window.location.reload()
  }
}
