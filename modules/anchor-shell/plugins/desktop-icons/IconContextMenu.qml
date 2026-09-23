import QtQuick
import qs.Commons

Rectangle {
    id: menuBox

    required property var host
    required property var surface
    visible: surface.menuKind !== ""
    z: 20
    width: menuCol.implicitWidth + 16
    height: menuCol.implicitHeight + 12
    radius: 8
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border
    x: Math.min(Math.max(8, menuX), Math.max(8, surface.width - width - 8))
    y: Math.min(Math.max(8, menuY), Math.max(8, surface.height - height - 8))

    // Bind plugin state onto this item so menu JS never needs the `panel` id.
    property var pluginHost: host
    property var currentItem: surface.menuItem
    property string currentScreen: surface.screenName
    property int closeTick: 0

    function activateMenu(action) {
        var item = currentItem;
        var plugin = pluginHost;
        var screenName = currentScreen;
        closeTick += 1;
        if (!plugin)
            return;
        if (action === "open")
            plugin.openOrConfirm(item, screenName);
        else if (action === "trust")
            plugin.allowLaunching(item);
        else if (action === "trust-open")
            plugin.trustAndOpen(item);
        else if (action === "trash")
            plugin.trashItem(item);
        else if (action === "rename")
            plugin.beginRename(item, screenName);
        else if (action === "files")
            plugin.revealItem(item);
    }

    Column {
        id: menuCol
        anchors.centerIn: parent
        width: Math.max(188, implicitWidth)
        spacing: 2

        Repeater {
            model: surface.menuEntries

            Rectangle {
                width: menuCol.width
                height: 28
                radius: 4
                color: rowMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : "transparent"

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    text: String(modelData.label || "")
                    textFormat: Text.PlainText
                    color: Color.popups.text
                    font.pixelSize: 13
                    font.family: Style.fontFamily
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: function (mouse) {
                        var action = String(modelData.action || "");
                        var node = rowMouse;
                        while (node) {
                            if (typeof node.activateMenu === "function") {
                                node.activateMenu(action);
                                return;
                            }
                            node = node.parent;
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: menuBox
        function onCloseTickChanged() {
            surface.menuKind = "";
            surface.menuItem = null;
        }
    }
}
