//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_IM_MODULE=fcitx

pragma ComponentBehavior: Bound
import "modules/clipboard"
import "services"
import "modules/clipboard/widgets"

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    id: root

    readonly property bool onDemand: (Quickshell.env("HANCORE_CLIPBOARD_ON_DEMAND") ?? "") === "1"
    readonly property bool hyprlandSession:
        (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
        || Quickshell.env("XDG_CURRENT_DESKTOP") === "Hyprland"
    readonly property string initialPosition:
        !root.hyprlandSession || (Quickshell.env("HANCORE_CLIPBOARD_POSITION") ?? "") === "bar"
            ? "bar" : "cursor"
    readonly property real initialBarHeight: Number(Quickshell.env("HANCORE_CLIPBOARD_BAR_HEIGHT") ?? "") || 32
    // Cursor-follow placement needs Hyprland IPC (`hyprctl cursorpos`).
    // wlroots compositors (labwc, sway, ...) expose no absolute pointer
    // position to clients, so cursor mode degrades to bar-anchored placement
    // there. Detected by probing the `hyprctl` socket — never env vars, which
    // can be stale across session switches.
    property bool isHyprland: false
    property real cursorX: 0
    property real cursorY: 0
    property real monitorX: 0
    property real monitorY: 0
    property var cursorScreen: null
    property bool cursorReady: false
    property bool positionReady: false
    property var cachedMonitors: []

    Component.onCompleted: {
        if (onDemand) {
            GlobalStates.clipboardOpen = true;
            dialog.positionMode = root.initialPosition;
            dialog.barHeight = root.initialBarHeight;
            // The open state is set before Connections can observe a change,
            // so explicitly sample the cursor for the on-demand process.
            Qt.callLater(root.updateCursorPosition);
        }
    }

    function updateCursorPosition() {
        if (!root.hyprlandSession) {
            dialog.positionMode = "bar";
            root.cursorReady = true;
            return;
        }
        root.cursorReady = false;
        positionReady = false;
        cursorPositionProc.running = false;
        cursorPositionProc.running = true;
    }

    Process {
        id: cursorPositionProc
        command: ["/run/current-system/sw/bin/hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const position = JSON.parse((text || "").trim());
                    root.cursorX = Number(position.x) || 0;
                    root.cursorY = Number(position.y) || 0;
                    root.cursorReady = true;
                    monitorProc.running = false;
                    monitorProc.running = true;
                    root.resolveMonitor();
                } catch (error) {
                    console.warn("[Clipboard] Could not read cursor position:", error);
                    cursorRetry.restart();
                }
            }
        }
        onExited: if (!root.cursorReady && GlobalStates.clipboardOpen)
            cursorRetry.restart()
    }

    Timer {
        id: cursorRetry
        interval: 150
        repeat: false
        onTriggered: if (GlobalStates.clipboardOpen) {
            cursorPositionProc.running = false;
            cursorPositionProc.running = true;
        }
    }

    function resolveMonitor() {
        if (root.cachedMonitors.length === 0) {
            monitorProc.running = false;
            monitorProc.running = true;
            return;
        }
        root.applyMonitor(root.cachedMonitors);
    }

    function applyMonitor(monitors) {
        if (root.isHyprland && !root.cursorReady)
            return;
        // wlroots compositors cannot report the pointer position, so cursor
        // mode falls back to the bar anchor. Must run before positionReady is
        // set: the window must never become visible in cursor mode on labwc.
        if (!root.isHyprland && dialog.positionMode !== "bar")
            dialog.positionMode = "bar";
        try {
            const monitor = monitors.find(candidate => {
                const rotated = candidate.transform === 1 || candidate.transform === 3
                    || candidate.transform === 5 || candidate.transform === 7;
                const scale = Number(candidate.scale) || 1;
                const logicalWidth = (rotated ? candidate.height : candidate.width) / scale;
                const logicalHeight = (rotated ? candidate.width : candidate.height) / scale;
                return root.cursorX >= candidate.x
                    && root.cursorX < candidate.x + logicalWidth
                    && root.cursorY >= candidate.y
                    && root.cursorY < candidate.y + logicalHeight;
            });
            if (monitor) {
                root.monitorX = Number(monitor.x) || 0;
                root.monitorY = Number(monitor.y) || 0;
                const screens = Quickshell.screens;
                let matchedScreen = null;
                for (let index = 0; index < screens.length; index++) {
                    if (screens[index].name === monitor.name) {
                        matchedScreen = screens[index];
                        break;
                    }
                }
                if (!matchedScreen) {
                    const rotated = monitor.transform === 1 || monitor.transform === 3
                        || monitor.transform === 5 || monitor.transform === 7;
                    const scale = Number(monitor.scale) || 1;
                    const logicalWidth = (rotated ? monitor.height : monitor.width) / scale;
                    const logicalHeight = (rotated ? monitor.width : monitor.height) / scale;
                    for (let index = 0; index < screens.length; index++) {
                        if (Math.abs(screens[index].width - logicalWidth) < 2
                                && Math.abs(screens[index].height - logicalHeight) < 2) {
                            matchedScreen = screens[index];
                            break;
                        }
                    }
                }
                if (matchedScreen)
                    root.cursorScreen = matchedScreen;
            }
        } catch (error) {
            console.warn("[Clipboard] Could not resolve cursor monitor:", error);
        }
        root.positionReady = true;
        Qt.callLater(() => dialog.place());
    }

    // Hyprland monitor layout. Doubles as the compositor probe: empty or
    // invalid output means no live Hyprland IPC socket, so we fall back to
    // wlr-randr (wlroots compositors: labwc, sway, ...).
    Process {
        id: monitorProc
        command: ["/run/current-system/sw/bin/hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let monitors = [];
                try {
                    const parsed = JSON.parse((text || "").trim());
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        root.isHyprland = true;
                        monitors = parsed;
                    }
                } catch (error) {
                    console.warn("[Clipboard] hyprctl monitors not ready, retrying:", error);
                    monitorRetry.restart();
                    return;
                }
                if (root.isHyprland) {
                    root.cachedMonitors = monitors;
                    root.applyMonitor(monitors);
                } else {
                    wlrMonitorProc.running = false;
                    wlrMonitorProc.running = true;
                }
            }
        }
        onExited: if (!root.isHyprland)
            monitorRetry.restart()
    }

    Timer {
        id: monitorRetry
        interval: 150
        repeat: false
        onTriggered: if (!root.isHyprland) {
            monitorProc.running = false;
            monitorProc.running = true;
        }
    }

    // wlroots fallback: normalized to the same shape as `hyprctl monitors -j`
    // (name/x/y/width/height/scale/transform) so applyMonitor() is shared.
    // wlr-randr reports the current mode in physical pixels and the position
    // in logical coordinates, exactly like Hyprland.
    Process {
        id: wlrMonitorProc
        command: ["wlr-randr", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const transformMap = {
                        "normal": 0, "90": 1, "180": 2, "270": 3,
                        "flipped": 4, "flipped-90": 5, "flipped-180": 6, "flipped-270": 7
                    };
                    const parsed = JSON.parse(text);
                    root.cachedMonitors = (parsed || [])
                        .filter(monitor => monitor.enabled)
                        .map(monitor => {
                            const mode = (monitor.modes || []).find(entry => entry.current) || {};
                            return {
                                name: monitor.name,
                                x: Number(monitor.position?.x) || 0,
                                y: Number(monitor.position?.y) || 0,
                                width: Number(mode.width) || 0,
                                height: Number(mode.height) || 0,
                                scale: Number(monitor.scale) || 1,
                                transform: transformMap[monitor.transform] ?? 0
                            };
                        });
                } catch (error) {
                    console.warn("[Clipboard] Could not parse wlr-randr monitors:", error);
                }
                root.applyMonitor(root.cachedMonitors);
            }
        }
    }

    // Close-after-warmup: hide on close, quit only if not reopened
    // within the warmup window. This avoids the Quickshell cold-start
    // cost when the clipboard is opened/closed repeatedly.
    readonly property int warmupMs: 25000

    Connections {
        target: GlobalStates
        function onClipboardOpenChanged() {
            if (GlobalStates.clipboardOpen) {
                warmupTimer.stop();
                root.updateCursorPosition();
            } else if (onDemand) {
                warmupTimer.restart();
            }
        }
    }

    Timer {
        id: warmupTimer
        interval: root.warmupMs
        repeat: false
        onTriggered: {
            if (onDemand && !GlobalStates.clipboardOpen)
                Qt.quit();
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle() {
            GlobalStates.clipboardOpen = !GlobalStates.clipboardOpen;
            // labwc has no cursor-position IPC, so bar mode is the only sane
            // placement. Setting "cursor" here would flash the menu at a stale
            // cursor position before applyMonitor() downgrades it.
            dialog.positionMode = root.isHyprland ? "cursor" : "bar";
        }
        function open() {
            GlobalStates.clipboardOpen = true;
            dialog.positionMode = root.isHyprland ? "cursor" : "bar";
        }
        function toggleAtBar(barHeight: real) {
            if (GlobalStates.clipboardOpen && dialog.positionMode === "bar") {
                GlobalStates.clipboardOpen = false;
            } else {
                GlobalStates.clipboardOpen = true;
                dialog.positionMode = "bar";
                if (barHeight > 0)
                    dialog.barHeight = barHeight;
            }
        }
        function openAtBar(barHeight: real) {
            GlobalStates.clipboardOpen = true;
            dialog.positionMode = "bar";
            if (barHeight > 0)
                dialog.barHeight = barHeight;
        }
        function close() {
            GlobalStates.clipboardOpen = false;
        }
    }

    PanelWindow {
        id: clipboardWindow
        // Keep this as a binding instead of assigning PanelWindow.screen after
        // creation. Wayland layershell output selection happens at creation;
        // a later imperative assignment can leave the layer on screen 1.
        screen: root.cursorScreen
        visible: GlobalStates.clipboardOpen && root.positionReady

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        implicitWidth: screen?.width ?? 0
        implicitHeight: screen?.height ?? 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.clipboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        function close() {
            GlobalStates.clipboardOpen = false;
        }

        Keys.onEscapePressed: {
            clipboardWindow.close();
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                clipboardWindow.close();
            }
        }

        ClipboardDialog {
            id: dialog
            anchors.fill: parent
            visible: GlobalStates.clipboardOpen
            show: GlobalStates.clipboardOpen
            cursorGlobalX: root.cursorX
            cursorGlobalY: root.cursorY
            screenGlobalX: root.monitorX
            screenGlobalY: root.monitorY
            screen: clipboardWindow.screen
            onDismiss: clipboardWindow.close()
        }
    }
}
