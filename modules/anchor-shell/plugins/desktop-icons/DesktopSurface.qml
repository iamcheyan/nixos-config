import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "DesktopLayout.js" as DesktopLayout

PanelWindow {
    id: panel
    required property var modelData

    // Repeater delegates with required properties cannot see outer ids.
    required property var host

    screen: modelData
    visible: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "desktop-icons"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    // Own the whole output so a selection can start from any edge.
    // Empty right-clicks are forwarded to Labwc's root menu.
    mask: Region {
        Region {
            item: emptyMouse
        }
        Region {
            item: menuBox
        }
        Region {
            item: trustBox
        }
    }

    readonly property string screenName: modelData.name || "default"
    property var visibleItems: []
    property int padTop: host.padTopFor(modelData)
    property int padLeft: host.padLeftFor(modelData)
    property string menuKind: ""
    property var menuItem: null
    property real menuX: 0
    property real menuY: 0
    property bool dropping: false
    property bool marqueeActive: false
    property bool marqueeMoved: false
    property bool suppressEmptyClick: false
    property real marqueeStartX: 0
    property real marqueeStartY: 0
    property real marqueeEndX: 0
    property real marqueeEndY: 0
    property var placedCells: ({})

    function posFor(item, index) {
        var grid = host.gridFor(panel.modelData);
        var cell = panel.placedCells[item && item.id];
        if (cell)
            return DesktopLayout.pixelFromCell(cell, grid);
        return DesktopLayout.position(host.layoutState, panel.screenName, item ? item.id : "", index, grid);
    }

    function refreshPlacedCells() {
        var ids = [];
        for (var i = 0; i < panel.visibleItems.length; i++)
            ids.push(panel.visibleItems[i].id);
        panel.placedCells = DesktopLayout.cellMap(host.layoutState, ids, panel.screenName, host.gridFor(panel.modelData));
    }

    function snap(x, y) {
        var grid = host.gridFor(panel.modelData);
        return DesktopLayout.pixelFromCell(DesktopLayout.cellFromPixel(x, y, grid), grid);
    }

    function itemFieldsMatch(a, b) {
        return !!(a && b && a.id === b.id && a.name === b.name && a.icon === b.icon && a.preview === b.preview && a.trusted === b.trusted && a.isDir === b.isDir && a.kind === b.kind && a.path === b.path);
    }

    function itemsMatch(current, next) {
        if (!current || !next || current.length !== next.length)
            return false;
        var byId = {};
        for (var i = 0; i < current.length; i++)
            byId[current[i].id] = current[i];
        for (var j = 0; j < next.length; j++) {
            if (!panel.itemFieldsMatch(byId[next[j].id], next[j]))
                return false;
        }
        return true;
    }

    function refreshVisibleItems() {
        var next = host.itemsForScreen(panel.screenName);
        if (panel.itemsMatch(panel.visibleItems, next)) {
            panel.refreshPlacedCells();
            return;
        }
        var byId = {};
        for (var i = 0; i < next.length; i++)
            byId[next[i].id] = next[i];
        var ordered = [];
        var seen = {};
        for (var j = 0; j < panel.visibleItems.length; j++) {
            var keep = byId[panel.visibleItems[j].id];
            if (keep && !seen[keep.id]) {
                ordered.push(keep);
                seen[keep.id] = true;
            }
        }
        for (var k = 0; k < next.length; k++) {
            if (!seen[next[k].id]) {
                ordered.push(next[k]);
                seen[next[k].id] = true;
            }
        }
        panel.visibleItems = ordered;
        panel.refreshPlacedCells();
    }

    function itemAt(x, y, exceptId) {
        for (var i = 0; i < panel.visibleItems.length; i++) {
            var item = panel.visibleItems[i];
            if (exceptId && item.id === exceptId)
                continue;
            var pos = panel.posFor(item, i);
            if (x >= pos.x && x < pos.x + host.cellW && y >= pos.y && y < pos.y + host.cellH)
                return item;
        }
        return null;
    }

    function selectMarquee() {
        var left = Math.min(panel.marqueeStartX, panel.marqueeEndX);
        var right = Math.max(panel.marqueeStartX, panel.marqueeEndX);
        var top = Math.min(panel.marqueeStartY, panel.marqueeEndY);
        var bottom = Math.max(panel.marqueeStartY, panel.marqueeEndY);
        var selected = [];
        for (var i = 0; i < panel.visibleItems.length; i++) {
            var pos = panel.posFor(panel.visibleItems[i], i);
            if (pos.x + host.cellW > left && pos.x < right && pos.y + host.cellH > top && pos.y < bottom)
                selected.push(panel.visibleItems[i]);
        }
        host.selectItems(selected);
    }

    function trustIconPos() {
        var item = host.pendingTrust;
        if (!item)
            return null;
        for (var i = 0; i < panel.visibleItems.length; i++) {
            if (panel.visibleItems[i].id === item.id)
                return panel.posFor(panel.visibleItems[i], i);
        }
        return null;
    }

    function closeMenu() {
        menuKind = "";
        menuItem = null;
    }

    function openItemMenu(item, iconItem, mouse) {
        menuKind = "item";
        menuItem = item;
        var p = contentItem.mapFromItem(iconItem, mouse.x, mouse.y);
        menuX = p.x;
        menuY = p.y;
    }

    readonly property var menuEntries: {
        if (menuKind === "item") {
            if (host.isTrash(menuItem))
                return [
                    {
                        action: "open",
                        label: "Open Trash"
                    },
                    {
                        action: "files",
                        label: "Show in Files"
                    }
                ];
            var renameAndManage = [
                {
                    action: "rename",
                    label: "Rename"
                },
                {
                    action: "files",
                    label: "Show in Files"
                },
                {
                    action: "trash",
                    label: "Move to Trash"
                }
            ];
            if (host.isUntrustedLauncher(menuItem))
                return [
                    {
                        action: "trust-open",
                        label: "Trust and Open"
                    },
                    {
                        action: "trust",
                        label: "Allow launching"
                    }
                ].concat(renameAndManage);
            return [
                {
                    action: "open",
                    label: "Open"
                }
            ].concat(renameAndManage);
        }
        return [];
    }

    MouseArea {
        id: emptyMouse
        z: 0
        anchors.fill: parent
        // Blank desktop input handles clicks only to dismiss plugin UI. Right
        // clicks on truly transparent wallpaper remain available to Labwc.
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        focus: true
        onActiveFocusChanged: {
            if (!activeFocus && !host.renamingId) {
                host.clearSelection();
                panel.closeMenu();
            }
        }
        onPressed: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                var dismiss = panel.menuKind !== "" || host.pendingTrust;
                panel.closeMenu();
                host.clearTrustPrompt();
                if (!dismiss)
                    host.showRootMenu();
                return;
            }
            if (mouse.button !== Qt.LeftButton)
                return;
            panel.marqueeActive = true;
            panel.marqueeMoved = false;
            panel.suppressEmptyClick = false;
            panel.marqueeStartX = mouse.x;
            panel.marqueeStartY = mouse.y;
            panel.marqueeEndX = mouse.x;
            panel.marqueeEndY = mouse.y;
            if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
                host.clearSelection();
            emptyMouse.forceActiveFocus();
            panel.closeMenu();
        }
        onPositionChanged: function (mouse) {
            if (!panel.marqueeActive || !(mouse.buttons & Qt.LeftButton))
                return;
            panel.marqueeEndX = mouse.x;
            panel.marqueeEndY = mouse.y;
            if (Math.abs(panel.marqueeEndX - panel.marqueeStartX) > 6 || Math.abs(panel.marqueeEndY - panel.marqueeStartY) > 6)
                panel.marqueeMoved = true;
        }
        onReleased: function (mouse) {
            if (mouse.button !== Qt.LeftButton || !panel.marqueeActive)
                return;
            if (panel.marqueeMoved) {
                panel.selectMarquee();
                panel.suppressEmptyClick = true;
            }
            panel.marqueeActive = false;
        }
        Keys.onPressed: function (event) {
            if (host.renamingId) {
                if (event.key === Qt.Key_Escape)
                    host.cancelRename();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Escape) {
                if (host.pendingTrust)
                    host.clearTrustPrompt();
                panel.closeMenu();
                event.accepted = true;
            } else if (event.key === Qt.Key_F2 && host.selectedIds.length === 1) {
                for (var r = 0; r < panel.visibleItems.length; r++) {
                    if (panel.visibleItems[r].id === host.selectedId) {
                        host.beginRename(panel.visibleItems[r], panel.screenName);
                        break;
                    }
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Delete && host.selectedIds.length > 0) {
                var paths = [];
                for (var i = 0; i < panel.visibleItems.length; i++) {
                    if (host.isSelected(panel.visibleItems[i].id) && panel.visibleItems[i].path)
                        paths.push(panel.visibleItems[i].path);
                }
                host.trashUrls(paths);
                host.clearSelection();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                for (var j = 0; j < panel.visibleItems.length; j++) {
                    if (panel.visibleItems[j].id === host.selectedId) {
                        host.openOrConfirm(panel.visibleItems[j], panel.screenName);
                        break;
                    }
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                host.moveSelection(event.modifiers & Qt.ShiftModifier ? -1 : 1, panel.screenName);
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab) {
                host.moveSelection(-1, panel.screenName);
                event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                host.moveSelectionDirection(-1, 0, panel.screenName);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                host.moveSelectionDirection(1, 0, panel.screenName);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                host.moveSelectionDirection(0, -1, panel.screenName);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                host.moveSelectionDirection(0, 1, panel.screenName);
                event.accepted = true;
            }
        }
        onClicked: function (mouse) {
            if (panel.suppressEmptyClick) {
                panel.suppressEmptyClick = false;
                return;
            }
            if (host.renamingId) {
                emptyMouse.forceActiveFocus();
                panel.closeMenu();
                return;
            }
            host.clearSelection();
            emptyMouse.forceActiveFocus();
            panel.closeMenu();
            if (host.pendingTrust) {
                host.clearTrustPrompt();
                return;
            }
            if (mouse.button === Qt.RightButton)
                return;
        }
    }

    DragGhost {
        host: panel.host
        surface: panel
    }

    Rectangle {
        id: marqueeBox
        visible: panel.marqueeActive && panel.marqueeMoved
        z: 4
        x: Math.min(panel.marqueeStartX, panel.marqueeEndX)
        y: Math.min(panel.marqueeStartY, panel.marqueeEndY)
        width: Math.abs(panel.marqueeEndX - panel.marqueeStartX)
        height: Math.abs(panel.marqueeEndY - panel.marqueeStartY)
        color: Qt.rgba(0.25, 0.55, 1.0, 0.16)
        border.width: 1
        border.color: Qt.rgba(0.45, 0.75, 1.0, 0.85)
    }

    DropArea {
        z: 0
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: panel.dropping = true
        onExited: panel.dropping = false
        onDropped: function (drop) {
            panel.dropping = false;
            var urls = [];
            if (drop.urls) {
                for (var i = 0; i < drop.urls.length; i++)
                    urls.push(String(drop.urls[i]));
            }
            if (urls.length > 0) {
                drop.acceptProposedAction();
                var target = panel.itemAt(drop.x, drop.y, "");
                if (target && host.isTrash(target))
                    host.trashUrls(urls);
                else
                    host.placeUrls(urls, host.dropMode(drop));
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: panel.dropping
        color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.35)
        z: 5
    }

    Item {
        id: inputLayer
        x: 0
        y: 0
        width: {
            var result = 1;
            for (var i = 0; i < panel.visibleItems.length; i++) {
                var item = panel.visibleItems[i];
                var pos = panel.posFor(item, i);
                result = Math.max(result, pos.x + panel.host.cellW);
            }
            return result;
        }
        height: {
            var result = 1;
            for (var i = 0; i < panel.visibleItems.length; i++) {
                var item = panel.visibleItems[i];
                var pos = panel.posFor(item, i);
                result = Math.max(result, pos.y + panel.host.cellH);
            }
            return result;
        }

        Repeater {
            model: panel.visibleItems

            DesktopIcon {
                host: panel.host
                surface: panel
                focusItem: emptyMouse
            }
        }

        IconContextMenu {
            id: menuBox
            host: panel.host
            surface: panel
        }
        Connections {
            target: host
            function onItemsChanged() {
                panel.refreshVisibleItems();
            }
            function onLayoutStateChanged() {
                panel.refreshVisibleItems();
            }
            function onScreenTopologyChanged() {
                panel.refreshVisibleItems();
            }
        }

        Component.onCompleted: panel.refreshVisibleItems()

        TrustPrompt {
            id: trustBox
            host: panel.host
            surface: panel
        }
    }
}
