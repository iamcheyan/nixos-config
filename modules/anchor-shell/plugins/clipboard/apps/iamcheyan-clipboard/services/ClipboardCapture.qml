import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    readonly property string captureScript: Qt.resolvedUrl("../../../backend/capture.sh").toString().replace("file://", "")
    // Remove watchers left by either the old Omarchy implementation or a
    // previous instance of this plugin before starting the single active pair.
    readonly property string watcherPattern: "wl-paste .*--watch .*(/shell/plugins/clipboard/capture\\.sh|iamcheyan\\.clipboard/backend/capture\\.sh)"

    function startWatchers() {
        textWatch.running = true;
        imageWatch.running = true;
    }

    Process {
        id: cleanupOldWatchers
        command: ["pkill", "-f", root.watcherPattern]
        onExited: root.startWatchers()
    }

    Process {
        id: textWatch
        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
        stdout: SplitParser { onRead: function(data) {} }
        onExited: restartTimer.restart()
    }

    Process {
        id: imageWatch
        command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
        stdout: SplitParser { onRead: function(data) {} }
        onExited: restartTimer.restart()
    }

    Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: root.startWatchers()
    }

    Component.onCompleted: cleanupOldWatchers.running = true
    Component.onDestruction: {
        textWatch.running = false;
        imageWatch.running = false;
    }
}
