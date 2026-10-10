import QtQuick
import Quickshell
import Quickshell.Io

// Adapter around Flux's stable newline-delimited Unix-socket IPC. The source
// component is provided by the pinned Flux package under QML_IMPORT_PATH.
Scope {
  id: root

  readonly property string socketPath: {
    var override = Quickshell.env("FLUX_SOCKET") || ""
    if (override !== "") return override
    var runtime = Quickshell.env("XDG_RUNTIME_DIR") || ""
    return runtime + "/flux/fluxd.sock"
  }
  readonly property int maxLine: 32 * 1024 * 1024
  readonly property bool connected: !!sock && sock.connected
  property bool attempted: false
  property var state: ({})
  readonly property var devices: state.devices || []
  readonly property var clipboard: state.clipboard || []
  readonly property var transfers: state.transfers || []
  readonly property var commands: state.commands || []
  readonly property var settings: state.settings || ({})
  readonly property var selfDevice: state.self || ({})
  signal toast(string text)
  property int nextId: 1
  property var pending: ({})
  property var sock: null
  readonly property int minRetryDelay: 2000
  readonly property int maxRetryDelay: 60000
  property int retryDelay: minRetryDelay

  function retryNow() {
    retryDelay = minRetryDelay
    connectNow()
  }

  function connectNow() {
    if (sock && sock.connected) return
    if (sock) sock.destroy()
    sock = socketComponent.createObject(root)
    sock.connected = true
  }

  function call(method, params, cb) {
    if (!sock || !sock.connected) {
      var offline = { code: "offline", message: "fluxd is not running" }
      if (cb) cb(offline, null)
      else toast(offline.message)
      return
    }
    var id = nextId++
    if (cb) pending[id] = cb
    sock.write(JSON.stringify({ id: id, method: method, params: params || {} }) + "\n")
    sock.flush()
  }

  function pickFiles(title, cb) {
    var proc = pickerComponent.createObject(root, {
      command: ["omarchy-file-select", "--title", String(title || "Send files"), "--multiple"]
    })
    proc.done = function (code, text) {
      var paths = code === 0 ? chooserPaths(String(text || "")) : []
      try { cb(paths) } catch (e) {}
    }
    proc.running = true
  }

  function chooserPaths(text) {
    if (text.endsWith("\n")) text = text.slice(0, -1)
    if (text === "") return []
    var paths = []
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith("/") || paths.length === 0) paths.push(lines[i])
      else paths[paths.length - 1] += "\n" + lines[i]
    }
    return paths.filter(function (p) { return p.startsWith("/") })
  }

  function startDaemon(cb) {
    var proc = pickerComponent.createObject(root, {
      command: ["sh", "-c", 'rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/flux/off"; systemctl --user start fluxd']
    })
    proc.done = function (code) {
      var ok = code === 0
      if (ok) root.retryNow()
      try { cb(ok, ok ? "" : "systemctl could not start fluxd. Run: journalctl --user -u fluxd") } catch (e) {}
    }
    proc.running = true
  }

  function handle(line) {
    if (!line || line.length === 0) return
    if (line.length > maxLine) {
      console.warn("flux: dropped an oversized line from fluxd")
      return
    }
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.event === "state") { state = msg.data || {}; return }
    if (msg.event === "toast") {
      if (msg.data && msg.data.text) toast(msg.data.text)
      return
    }
    if (msg.id === undefined) return
    var cb = pending[msg.id]
    delete pending[msg.id]
    try {
      if (msg.error) {
        if (cb) cb(msg.error, null)
        else toast(msg.error.message || msg.error.code || "Error")
      } else if (cb) cb(null, msg.result || {})
    } catch (e) {}
  }

  function failPending() {
    var waiting = pending
    pending = ({})
    for (var id in waiting)
      try { waiting[id]({ code: "offline", message: "fluxd is not running" }, null) } catch (e) {}
  }

  Component {
    id: pickerComponent
    Process {
      id: proc
      property var done: null
      stdout: StdioCollector { id: out; waitForEnd: true }
      onExited: function (code) {
        if (proc.done) proc.done(code, out.text)
        proc.destroy()
      }
    }
  }

  Component {
    id: socketComponent
    Socket {
      id: socket
      path: root.socketPath
      parser: SplitParser { onRead: data => root.handle(data) }
      onConnectedChanged: {
        if (socket !== root.sock) return
        root.attempted = true
        if (connected) {
          root.retryDelay = root.minRetryDelay
          root.call("subscribe", {}, null)
        } else root.failPending()
      }
      onError: root.attempted = true
    }
  }

  Component.onCompleted: connectNow()

  Timer {
    interval: root.retryDelay
    repeat: true
    running: !root.connected
    onTriggered: {
      root.attempted = true
      root.retryDelay = Math.min(root.retryDelay * 2, root.maxRetryDelay)
      root.connectNow()
    }
  }
}
