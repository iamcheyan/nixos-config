import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "DesktopLayout.js" as DesktopLayout

Item {
    id: iconRoot

    required property var host
    required property var panel
    required property var emptyMouse
    required property var modelData
    required property int index

    width: panel.host.cellW
    height: panel.host.cellH
    z: iconMouse.drag.active ? 6 : 2
    opacity: (panel.host.dragId === iconRoot.modelData.id && panel.host.dragHoverScreen !== "" && panel.host.dragHoverScreen !== panel.screenName) ? 0 : 1
    property real pressX: 0
    property real pressY: 0
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property real lastSceneX: 0
    property real lastSceneY: 0

    Binding on x {
        value: panel.posFor(iconRoot.modelData, iconRoot.index).x
        when: !iconMouse.drag.active
        restoreMode: Binding.RestoreNone
    }
    Binding on y {
        value: panel.posFor(iconRoot.modelData, iconRoot.index).y
        when: !iconMouse.drag.active
        restoreMode: Binding.RestoreNone
    }

    Rectangle {
        width: Math.max(panel.host.iconSize + 12, Math.min(parent.width - 8, labelText.implicitWidth + 12))
        height: Math.min(parent.height - 8, panel.host.iconSize + labelText.paintedHeight + 16)
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 8
        property bool selected: panel.host.isSelected(iconRoot.modelData.id) && emptyMouse.activeFocus
        color: selected ? Qt.rgba(1, 1, 1, 0.18) : (iconHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
        border.width: selected ? 1 : 0
        border.color: Qt.rgba(1, 1, 1, 0.35)
    }

    HoverHandler {
        id: iconHover
    }

    Column {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        Item {
            width: panel.host.iconSize
            height: panel.host.iconSize
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                id: fallbackGlyph
                anchors.fill: parent
                source: panel.host.fallbackIcon(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: false
                smooth: true
                visible: iconImage.status === Image.Error
                sourceSize.width: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
                sourceSize.height: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
            }

            Image {
                id: iconImage
                anchors.fill: parent
                source: panel.host.iconSource(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                // Pop theme icons are SVG. Qt SVG is not thread-safe, so an
                // asynchronous decode often comes back blank while the label
                // still paints. A failed decode also poisons Image.cache.
                asynchronous: false
                cache: false
                smooth: true
                visible: status !== Image.Error
                sourceSize.width: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
                sourceSize.height: panel.host.iconIsRaster(source) ? panel.host.iconPixels : 0
            }

            Rectangle {
                visible: panel.host.isUntrustedLauncher(iconRoot.modelData)
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 20
                height: 20
                radius: 10
                color: "#cc8a1515"
                border.width: 1
                border.color: "#eeffffff"

                Text {
                    anchors.centerIn: parent
                    text: "!"
                    textFormat: Text.PlainText
                    color: "white"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: Style.fontFamily
                }
            }
        }

        Text {
            id: labelText
            visible: !panel.host.isRenamingItem(iconRoot.modelData, panel.screenName)
            width: parent.width
            text: panel.host.plainText(iconRoot.modelData.name)
            textFormat: Text.PlainText
            color: "white"
            style: Text.Outline
            styleColor: "#cc000000"
            font.pixelSize: 12
            font.family: Style.fontFamily
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Rectangle {
        visible: panel.host.isRenamingItem(iconRoot.modelData, panel.screenName)
        z: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: 46
        radius: 4
        color: "#ee1a1a1a"
        border.width: 1
        border.color: "#88ffffff"

        TextInput {
            id: renameInput
            anchors.fill: parent
            anchors.margins: 4
            color: "white"
            font.pixelSize: 16
            font.family: Style.fontFamily
            wrapMode: TextInput.Wrap
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            clip: true
            maximumLength: 255
            property bool finishing: false
            property bool ready: false

            function commit() {
                if (finishing)
                    return;
                finishing = true;
                panel.host.commitRename(iconRoot.modelData, text);
            }

            function cancel() {
                if (finishing)
                    return;
                finishing = true;
                panel.host.cancelRename();
            }

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    commit();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    cancel();
                    event.accepted = true;
                }
            }
            onVisibleChanged: {
                if (visible) {
                    finishing = false;
                    ready = false;
                    text = panel.host.plainText(iconRoot.modelData.name);
                    Qt.callLater(function () {
                        if (!panel.host.isRenamingItem(iconRoot.modelData, panel.screenName))
                            return;
                        renameInput.forceActiveFocus();
                        renameInput.selectAll();
                        renameInput.ready = true;
                    });
                } else {
                    ready = false;
                }
            }
            onActiveFocusChanged: {
                if (visible && ready && !activeFocus)
                    commit();
            }
        }
    }

    MouseArea {
        id: iconMouse
        anchors.fill: parent
        z: 2
        enabled: !panel.host.isRenamingItem(iconRoot.modelData, panel.screenName)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        drag.target: iconRoot
        drag.axis: Drag.XAndYAxis
        drag.threshold: 8
        // Do not clamp the dragged item to this output. The pointer grab
        // must be allowed to cross the virtual desktop so the release
        // handler can transfer the item to the other output.
        drag.minimumX: -panel.width * 2
        drag.minimumY: -panel.height * 2
        drag.maximumX: panel.width * 2
        drag.maximumY: panel.height * 2
        onPressed: function (mouse) {
            iconRoot.pressX = iconRoot.x;
            iconRoot.pressY = iconRoot.y;
            iconRoot.dragOffsetX = mouse.x;
            iconRoot.dragOffsetY = mouse.y;
            iconRoot.lastSceneX = panel.modelData.x + iconRoot.x + mouse.x;
            iconRoot.lastSceneY = panel.modelData.y + iconRoot.y + mouse.y;
            panel.host.selectItem(iconRoot.modelData, mouse.modifiers);
            emptyMouse.forceActiveFocus();
            if (mouse.button === Qt.LeftButton)
                panel.host.beginDrag(iconRoot.modelData, panel.screenName, iconRoot.lastSceneX, iconRoot.lastSceneY, mouse.x, mouse.y);
        }
        onPositionChanged: function (mouse) {
            if (!(mouse.buttons & Qt.LeftButton))
                return;
            iconRoot.lastSceneX = panel.modelData.x + iconRoot.x + mouse.x;
            iconRoot.lastSceneY = panel.modelData.y + iconRoot.y + mouse.y;
            panel.host.updateDragPointer(iconRoot.lastSceneX, iconRoot.lastSceneY);
        }
        onCanceled: panel.host.clearDrag()
        onReleased: function (mouse) {
            if (mouse.button !== Qt.LeftButton) {
                panel.host.clearDrag();
                return;
            }
            var itemId = iconRoot.modelData.id;
            var fromScreen = panel.screenName;
            var sceneX = iconRoot.lastSceneX;
            var sceneY = iconRoot.lastSceneY;
            var grabX = iconRoot.dragOffsetX;
            var grabY = iconRoot.dragOffsetY;
            var pressX = iconRoot.pressX;
            var pressY = iconRoot.pressY;
            var dropX = iconRoot.x;
            var dropY = iconRoot.y;
            var wasDragged = Math.abs(dropX - pressX) > 8 || Math.abs(dropY - pressY) > 8;
            // Hide the follow-cursor ghost before any layout change.
            // moveItemToScreen removes this id from the source screen, which
            // destroys this delegate and would skip a clearDrag() after it.
            panel.host.clearDrag();
            if (!wasDragged)
                return;
            var targetScreen = panel.host.screenAtPoint(sceneX, sceneY);
            if (targetScreen && String(targetScreen.name || "default") !== fromScreen && Quickshell.screens.length > 1) {
                panel.host.moveItemToScreen(itemId, fromScreen, String(targetScreen.name || "default"), sceneX - targetScreen.x - grabX, sceneY - targetScreen.y - grabY);
                return;
            }
            var target = panel.itemAt(dropX + iconRoot.width / 2, dropY + iconRoot.height / 2, itemId);
            if (target && panel.host.isTrash(target) && !panel.host.isTrash(iconRoot.modelData)) {
                panel.host.trashItem(iconRoot.modelData);
                return;
            }
            var snapped = panel.snap(dropX, dropY);
            var grid = panel.host.gridFor(panel.modelData);
            var sourceCell = DesktopLayout.cellFromPixel(pressX, pressY, grid);
            var targetCell = DesktopLayout.cellFromPixel(snapped.x, snapped.y, grid);
            iconRoot.x = snapped.x;
            iconRoot.y = snapped.y;
            panel.host.moveItemWithinScreen(fromScreen, itemId, sourceCell, targetCell);
        }
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                if (!panel.host.isSelected(iconRoot.modelData.id))
                    panel.host.selectItem(iconRoot.modelData, 0);
                panel.openItemMenu(iconRoot.modelData, iconRoot, mouse);
                return;
            }
            if (iconMouse.drag.active)
                return;
            if (Math.abs(iconRoot.x - iconRoot.pressX) > 8 || Math.abs(iconRoot.y - iconRoot.pressY) > 8)
                return;
            panel.closeMenu();
        }
        onDoubleClicked: function (mouse) {
            if (mouse.button !== Qt.LeftButton || iconMouse.drag.active)
                return;
            panel.closeMenu();
            panel.host.openOrConfirm(iconRoot.modelData, panel.screenName);
        }
    }

    DropArea {
        anchors.fill: parent
        z: 3
        enabled: panel.host.isTrash(iconRoot.modelData)
        keys: ["text/uri-list"]
        onEntered: panel.dropping = true
        onExited: panel.dropping = false
        onDropped: function (drop) {
            panel.dropping = false;
            if (!panel.host.isTrash(iconRoot.modelData))
                return;
            var urls = [];
            if (drop.urls) {
                for (var i = 0; i < drop.urls.length; i++)
                    urls.push(String(drop.urls[i]));
            }
            if (urls.length > 0) {
                drop.acceptProposedAction();
                panel.host.trashUrls(urls);
            }
        }
    }
}
