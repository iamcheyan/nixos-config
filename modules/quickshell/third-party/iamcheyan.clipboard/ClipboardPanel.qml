import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "apps/iamcheyan-clipboard/modules/clipboard"

Panel {
    id: root
    moduleName: "iamcheyan.clipboard"
    manageIpc: false
    property var anchorItem: null
    property var hostWidget: null
    property bool cursorMode: false
    property bool cursorReady: false
    property real cursorGlobalX: 0
    property real cursorGlobalY: 0
    property real cursorScreenX: 0
    property real cursorScreenY: 0
    property var cursorScreen: null
    property var cursorMonitors: []

    function open() { root.openAtBar(); }
    function openAtBar() {
        root.cursorMode = false;
        root.cursorReady = true;
        root.controller.show();
    }
    function openAtCursor() {
        if (!root.hyprlandSession) {
            root.openAtBar();
            return;
        }
        root.cursorMode = true;
        root.cursorReady = false;
        cursorPositionProcess.running = true;
        root.controller.show();
    }
    function close() { root.controller.hide(); }
    function toggle() { root.opened ? root.close() : root.open(); }

    function updateCursorPlacement() {
        if (root.cursorMode && root.cursorReady && clipboardDialog.visible)
            clipboardDialog.place();
    }

    // During a monitor hotplug or Hyprland lock transition QsWindow can be
    // temporarily unavailable. Never let the panel bind to a placeholder
    // QScreen; that would make Quickshell create a layershell on a non-output.
    function barScreen() {
        if (!root.anchorItem || !root.anchorItem.QsWindow || !root.anchorItem.QsWindow.window)
            return null;
        return root.anchorItem.QsWindow.window.screen || null;
    }

    function validScreen(candidate) {
        return candidate && candidate.name && candidate.width > 0 && candidate.height > 0;
    }

    readonly property bool hyprlandSession:
        (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").length > 0
        || Quickshell.env("XDG_CURRENT_DESKTOP") === "Hyprland"

    Process {
        id: cursorPositionProcess
        command: ["/run/current-system/sw/bin/hyprctl", "cursorpos", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const position = JSON.parse((text || "{}").trim());
                    root.cursorGlobalX = Number(position.x) || 0;
                    root.cursorGlobalY = Number(position.y) || 0;
                    monitorPositionProcess.running = true;
                } catch (error) {
                    cursorRetry.restart();
                }
            }
        }
        onExited: if (root.cursorMode && !root.cursorReady)
            cursorRetry.restart()
    }

    Timer {
        id: cursorRetry
        interval: 150
        repeat: false
        onTriggered: if (root.cursorMode && !root.cursorReady) {
            cursorPositionProcess.running = false;
            cursorPositionProcess.running = true;
        }
    }

    onCursorGlobalXChanged: root.updateCursorPlacement()
    onCursorGlobalYChanged: root.updateCursorPlacement()
    onCursorScreenXChanged: root.updateCursorPlacement()
    onCursorScreenYChanged: root.updateCursorPlacement()

    // QScreen's x/y values are not a reliable representation of Hyprland's
    // global layout on every Quickshell/Qt combination. Use Hyprland's own
    // monitor geometry so a cursor on a secondary (or negative-offset) output
    // selects the matching layershell screen.
    Process {
        id: monitorPositionProcess
        command: ["/run/current-system/sw/bin/hyprctl", "monitors", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const monitors = JSON.parse((text || "[]").trim());
                    root.cursorMonitors = Array.isArray(monitors) ? monitors : [];
                    root.resolveCursorScreen();
                } catch (error) {
                    root.cursorMonitors = [];
                    monitorRetry.restart();
                }
            }
        }
        onExited: if (root.cursorMode && !root.cursorReady)
            monitorRetry.restart()
    }

    Timer {
        id: monitorRetry
        interval: 150
        repeat: false
        onTriggered: if (root.cursorMode && !root.cursorReady) {
            monitorPositionProcess.running = false;
            monitorPositionProcess.running = true;
        }
    }

    function resolveCursorScreen() {
        for (let index = 0; index < root.cursorMonitors.length; index++) {
            const monitor = root.cursorMonitors[index];
            const rotated = monitor.transform === 1 || monitor.transform === 3
                || monitor.transform === 5 || monitor.transform === 7;
            const scale = Number(monitor.scale) || 1;
            const monitorWidth = (rotated ? monitor.height : monitor.width) / scale;
            const monitorHeight = (rotated ? monitor.width : monitor.height) / scale;
            if (root.cursorGlobalX >= monitor.x
                    && root.cursorGlobalX < monitor.x + monitorWidth
                    && root.cursorGlobalY >= monitor.y
                    && root.cursorGlobalY < monitor.y + monitorHeight) {
                const screens = Quickshell.screens;
                let matchedScreen = null;
                for (let screenIndex = 0; screenIndex < screens.length; screenIndex++) {
                    if (screens[screenIndex].name === monitor.name) {
                        matchedScreen = screens[screenIndex];
                        break;
                    }
                }
                // On some Qt/Wayland versions QScreen.name is not the
                // connector name. Match its logical geometry next.
                if (!matchedScreen) {
                    for (let screenIndex = 0; screenIndex < screens.length; screenIndex++) {
                        const candidate = screens[screenIndex];
                        if (Math.abs(candidate.width - monitorWidth) < 2
                                && Math.abs(candidate.height - monitorHeight) < 2) {
                            matchedScreen = candidate;
                            break;
                        }
                    }
                }
                if (matchedScreen) {
                    root.cursorScreen = matchedScreen;
                    root.cursorScreenX = Number(monitor.x) || 0;
                    root.cursorScreenY = Number(monitor.y) || 0;
                    root.cursorReady = true;
                    return;
                }
            }
        }

        // Keep a Qt-screen fallback for compositors or older Hyprland builds
        // that do not return monitor JSON.
        const screens = Quickshell.screens;
        for (let index = 0; index < screens.length; index++) {
            const candidate = screens[index];
            if (root.cursorGlobalX >= candidate.x
                    && root.cursorGlobalX < candidate.x + candidate.width
                    && root.cursorGlobalY >= candidate.y
                    && root.cursorGlobalY < candidate.y + candidate.height) {
                root.cursorScreen = candidate;
                root.cursorScreenX = candidate.x;
                root.cursorScreenY = candidate.y;
                root.cursorReady = true;
                return;
            }
        }
        root.cursorReady = true;
    }

    // Use Omarchy's own anchor/cardOrigin calculation, but keep the original
    // transparent full-screen menu surface so KeyboardPanel's card background
    // is never painted behind the clipboard UI.
    KeyboardPanel {
        id: geometry
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: false
        padding: 0
        borderSpec: Border.none()
        contentWidth: geometry.fittedContentWidth(clipboardDialog.menuWidth + clipboardDialog.previewWidth + 10)
        contentHeight: geometry.fittedContentHeight(clipboardDialog.menuHeight)
    }

    PanelWindow {
        id: clipboardWindow
        property var targetScreen: root.cursorMode ? root.cursorScreen
            : root.barScreen()
        screen: targetScreen
        visible: root.opened
            && (!root.cursorMode || root.cursorReady)
            && root.validScreen(targetScreen)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        ClipboardDialog {
            id: clipboardDialog
            z: 1
            x: root.cursorMode ? 0 : geometry.cardOrigin.x
            y: root.cursorMode ? 0 : geometry.cardOrigin.y
            width: root.cursorMode ? clipboardWindow.width : geometry.contentWidth
            height: root.cursorMode ? clipboardWindow.height : geometry.contentHeight
            screen: clipboardWindow.targetScreen
            visible: clipboardWindow.visible
            show: root.opened
            embedded: !root.cursorMode
            positionMode: root.cursorMode ? "cursor" : "bar"
            cursorGlobalX: root.cursorGlobalX
            cursorGlobalY: root.cursorGlobalY
            screenGlobalX: root.cursorScreenX
            screenGlobalY: root.cursorScreenY
            onDismiss: root.close()
        }

        MouseArea {
            anchors.fill: parent
            z: 0
            onClicked: root.close()
        }

        Keys.onEscapePressed: root.close()
    }
}
