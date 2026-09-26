import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "DesktopLayout.js" as DesktopLayout

Item {
    id: iconRoot

    required property var host
    required property var surface
    required property var focusItem
    required property var modelData
    required property int index

    width: surface.host.cellW
    height: surface.host.cellH
    z: iconMouse.drag.active ? 6 : (surface.host.isDraggingItem(modelData.id) ? 5 : 2)
    opacity: (surface.host.dragId === iconRoot.modelData.id && surface.host.dragHoverScreen !== "" && surface.host.dragHoverScreen !== surface.screenName) ? 0 : 1
    property real pressX: 0
    property real pressY: 0
    property real dragOffsetX: 0
    property real dragOffsetY: 0
    property real lastSceneX: 0
    property real lastSceneY: 0

    Binding on x {
        value: surface.host.isDraggingItem(iconRoot.modelData.id)
            ? surface.host.dragStarts[iconRoot.modelData.id].x + surface.host.dragDeltaX
            : surface.posFor(iconRoot.modelData, iconRoot.index).x
        when: !iconMouse.drag.active
        restoreMode: Binding.RestoreNone
    }
    Binding on y {
        value: surface.host.isDraggingItem(iconRoot.modelData.id)
            ? surface.host.dragStarts[iconRoot.modelData.id].y + surface.host.dragDeltaY
            : surface.posFor(iconRoot.modelData, iconRoot.index).y
        when: !iconMouse.drag.active
        restoreMode: Binding.RestoreNone
    }

    Rectangle {
        width: Math.max(surface.host.iconSize + 12, Math.min(parent.width - 8, labelText.implicitWidth + 12))
        height: Math.min(parent.height - 8, surface.host.iconSize + labelText.paintedHeight + 16)
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 8
        property bool selected: surface.host.isSelected(iconRoot.modelData.id) && focusItem.activeFocus
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
            width: surface.host.iconSize
            height: surface.host.iconSize
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                id: fallbackGlyph
                anchors.fill: parent
                source: surface.host.fallbackIcon(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: false
                smooth: true
                visible: iconImage.status === Image.Error
                sourceSize.width: surface.host.iconIsRaster(source) ? surface.host.iconPixels : 0
                sourceSize.height: surface.host.iconIsRaster(source) ? surface.host.iconPixels : 0
            }

            Image {
                id: iconImage
                anchors.fill: parent
                source: surface.host.iconSource(iconRoot.modelData)
                fillMode: Image.PreserveAspectFit
                // Pop theme icons are SVG. Qt SVG is not thread-safe, so an
                // asynchronous decode often comes back blank while the label
                // still paints. A failed decode also poisons Image.cache.
                asynchronous: false
                cache: false
                smooth: true
                visible: status !== Image.Error
                sourceSize.width: surface.host.iconIsRaster(source) ? surface.host.iconPixels : 0
                sourceSize.height: surface.host.iconIsRaster(source) ? surface.host.iconPixels : 0
            }

            Rectangle {
                visible: surface.host.isUntrustedLauncher(iconRoot.modelData)
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

        Item {
            width: parent.width
            height: labelText.implicitHeight + 1

            Text {
                id: labelShadow
                visible: !surface.host.isRenamingItem(iconRoot.modelData, surface.screenName)
                x: 1
                y: 1
                width: parent.width
                text: surface.host.plainText(iconRoot.modelData.name)
                textFormat: Text.PlainText
                color: "#b3000000"
                font.pixelSize: 12
                font.family: Style.fontFamily
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                id: labelText
                visible: !surface.host.isRenamingItem(iconRoot.modelData, surface.screenName)
                width: parent.width
                text: surface.host.plainText(iconRoot.modelData.name)
                textFormat: Text.PlainText
                color: "white"
                font.pixelSize: 12
                font.family: Style.fontFamily
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Rectangle {
        visible: surface.host.isRenamingItem(iconRoot.modelData, surface.screenName)
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
                surface.host.commitRename(iconRoot.modelData, text);
            }

            function cancel() {
                if (finishing)
                    return;
                finishing = true;
                surface.host.cancelRename();
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
                    text = surface.host.plainText(iconRoot.modelData.name);
                    Qt.callLater(function () {
                        if (!surface.host.isRenamingItem(iconRoot.modelData, surface.screenName))
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
        enabled: !surface.host.isRenamingItem(iconRoot.modelData, surface.screenName)
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
        drag.minimumX: -surface.width * 2
        drag.minimumY: -surface.height * 2
        drag.maximumX: surface.width * 2
        drag.maximumY: surface.height * 2
        onPressed: function (mouse) {
            iconRoot.pressX = iconRoot.x;
            iconRoot.pressY = iconRoot.y;
            iconRoot.dragOffsetX = mouse.x;
            iconRoot.dragOffsetY = mouse.y;
            iconRoot.lastSceneX = surface.modelData.x + iconRoot.x + mouse.x;
            iconRoot.lastSceneY = surface.modelData.y + iconRoot.y + mouse.y;
            if (!surface.host.isSelected(iconRoot.modelData.id)
                || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
                surface.host.selectItem(iconRoot.modelData, mouse.modifiers);
            focusItem.forceActiveFocus();
            // Wait until the pointer actually moves before starting a drag.
            // Starting on press jumps the Binding and eats double-clicks.
        }
        onPositionChanged: function (mouse) {
            if (!(mouse.buttons & Qt.LeftButton))
                return;
            iconRoot.lastSceneX = surface.modelData.x + iconRoot.x + mouse.x;
            iconRoot.lastSceneY = surface.modelData.y + iconRoot.y + mouse.y;
            var moved = Math.abs(iconRoot.x - iconRoot.pressX) > 8 || Math.abs(iconRoot.y - iconRoot.pressY) > 8
                || Math.abs(mouse.x - iconRoot.dragOffsetX) > 8 || Math.abs(mouse.y - iconRoot.dragOffsetY) > 8;
            if (surface.host.dragId === "" && moved)
                surface.host.beginDrag(iconRoot.modelData, surface.screenName, iconRoot.lastSceneX, iconRoot.lastSceneY, iconRoot.dragOffsetX, iconRoot.dragOffsetY);
            if (surface.host.dragId === "")
                return;
            surface.host.updateGroupDrag(iconRoot.x - iconRoot.pressX, iconRoot.y - iconRoot.pressY);
            surface.host.updateDragPointer(iconRoot.lastSceneX, iconRoot.lastSceneY);
        }
        onCanceled: surface.host.clearDrag()
        onReleased: function (mouse) {
            if (mouse.button !== Qt.LeftButton) {
                surface.host.clearDrag();
                return;
            }
            var itemId = iconRoot.modelData.id;
            var fromScreen = surface.screenName;
            var sceneX = iconRoot.lastSceneX;
            var sceneY = iconRoot.lastSceneY;
            var grabX = iconRoot.dragOffsetX;
            var grabY = iconRoot.dragOffsetY;
            var dropX = iconRoot.x;
            var dropY = iconRoot.y;
            var wasDragged = surface.host.dragId !== "";
            var draggedIds = surface.host.dragIds.slice();
            var draggedStarts = JSON.parse(JSON.stringify(surface.host.dragStarts));
            // Hide the follow-cursor ghost before any layout change.
            // A cross-screen group move can remove this delegate immediately,
            // so keep the drag snapshot before clearing the shared drag state.
            surface.host.clearDrag();
            if (!wasDragged)
                return;
            var targetScreen = surface.host.screenAtPoint(sceneX, sceneY);
            if (targetScreen && String(targetScreen.name || "default") !== fromScreen && Quickshell.screens.length > 1) {
                var targetName = String(targetScreen.name || "default");
                var targetGrid = surface.host.gridFor(targetScreen);
                var targetX = sceneX - targetScreen.x - grabX;
                var targetY = sceneY - targetScreen.y - grabY;
                var targetCell = DesktopLayout.cellFromPixel(targetX, targetY, targetGrid);
                surface.host.moveDraggedGroup(fromScreen, targetName, targetCell, itemId, draggedIds, draggedStarts);
                return;
            }
            var target = surface.itemAt(dropX + iconRoot.width / 2, dropY + iconRoot.height / 2, itemId);
            if (target && surface.host.isTrash(target) && !surface.host.isTrash(iconRoot.modelData)) {
                var draggedItems = [];
                for (var selectedIndex = 0; selectedIndex < draggedIds.length; selectedIndex++) {
                    for (var visibleIndex = 0; visibleIndex < surface.visibleItems.length; visibleIndex++) {
                        if (surface.visibleItems[visibleIndex].id === draggedIds[selectedIndex])
                            draggedItems.push(surface.visibleItems[visibleIndex]);
                    }
                }
                var paths = [];
                for (var draggedIndex = 0; draggedIndex < draggedItems.length; draggedIndex++) {
                    if (draggedItems[draggedIndex].path && !surface.host.isTrash(draggedItems[draggedIndex]))
                        paths.push(draggedItems[draggedIndex].path);
                }
                surface.host.trashUrls(paths.length ? paths : [iconRoot.modelData.path]);
                return;
            }
            var snapped = surface.snap(dropX, dropY);
            var grid = surface.host.gridFor(surface.modelData);
            var targetCell = DesktopLayout.cellFromPixel(snapped.x, snapped.y, grid);
            iconRoot.x = snapped.x;
            iconRoot.y = snapped.y;
            surface.host.moveDraggedGroup(fromScreen, fromScreen, targetCell, itemId, draggedIds, draggedStarts);
        }
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                if (!surface.host.isSelected(iconRoot.modelData.id))
                    surface.host.selectItem(iconRoot.modelData, 0);
                surface.openItemMenu(iconRoot.modelData, iconRoot, mouse);
                return;
            }
            if (iconMouse.drag.active)
                return;
            if (Math.abs(iconRoot.x - iconRoot.pressX) > 8 || Math.abs(iconRoot.y - iconRoot.pressY) > 8)
                return;
            surface.closeMenu();
        }
        onDoubleClicked: function (mouse) {
            if (mouse.button !== Qt.LeftButton || iconMouse.drag.active)
                return;
            surface.closeMenu();
            surface.host.openOrConfirm(iconRoot.modelData, surface.screenName);
        }
    }

    DropArea {
        anchors.fill: parent
        z: 3
        enabled: surface.host.isTrash(iconRoot.modelData)
        keys: ["text/uri-list"]
        onEntered: surface.dropping = true
        onExited: surface.dropping = false
        onDropped: function (drop) {
            surface.dropping = false;
            if (!surface.host.isTrash(iconRoot.modelData))
                return;
            var urls = [];
            if (drop.urls) {
                for (var i = 0; i < drop.urls.length; i++)
                    urls.push(String(drop.urls[i]));
            }
            if (urls.length > 0) {
                drop.acceptProposedAction();
                surface.host.trashUrls(urls);
            }
        }
    }
}
