import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "iamcheyan.clipboard"

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function injectPanel() {
        if (!panelLoader.item) return;
        panelLoader.item.bar = root.bar;
        panelLoader.item.anchorItem = button;
        panelLoader.item.hostWidget = root;
    }
    function open() {
        if (!panelLoader.item) {
            panelLoader.active = true;
            Qt.callLater(function() { if (panelLoader.item) panelLoader.item.open(); });
        } else panelLoader.item.open();
    }
    function openAtBar() {
        if (!panelLoader.item) {
            panelLoader.active = true;
            Qt.callLater(function() { if (panelLoader.item) panelLoader.item.openAtBar(); });
        } else panelLoader.item.openAtBar();
    }
    function openAtCursor() {
        if (!panelLoader.item) {
            panelLoader.active = true;
            Qt.callLater(function() { if (panelLoader.item) panelLoader.item.openAtCursor(); });
        } else panelLoader.item.openAtCursor();
    }
    function close() { if (panelLoader.item) panelLoader.item.close(); }
    function toggleAtBar() { root.opened ? root.close() : root.openAtBar(); }
    onBarChanged: injectPanel()

    IpcHandler {
        target: "iamcheyan.clipboard"
        function toggleAtCursor(): void { root.opened ? root.close() : root.openAtCursor(); }
        function openAtCursor(): void { root.openAtCursor(); }
        function toggle(): void { root.opened ? root.close() : root.openAtCursor(); }
        function open(): void { root.openAtCursor(); }
        function close(): void { root.close(); }
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("../ClipboardPanel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
    }

    BarIconButton {
        id: button
        bar: root.bar
        text: "󰅌"
        tooltipText: "Clipboard history"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggleAtBar();
        }
    }
}
