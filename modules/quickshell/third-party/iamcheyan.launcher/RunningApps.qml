import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false
  property var runningSet: ({})

  function refresh() {
    clientsProc.running = false
    clientsProc.running = true
  }

  function update(text) {
    try {
      var clients = JSON.parse(text || "[]")
      var next = ({})
      for (var i = 0; i < clients.length; i++) {
        var client = clients[i]
        if (!client || !client.mapped || client.hidden) continue
        if (client.class) next[String(client.class).toLowerCase()] = true
        if (client.initialClass) next[String(client.initialClass).toLowerCase()] = true
      }
      root.runningSet = next
    } catch (error) {
      root.runningSet = ({})
    }
  }

  Component.onCompleted: refresh()

  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      id: collector
      onStreamFinished: root.update(collector.text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.runningSet = ({})
    }
  }
}
