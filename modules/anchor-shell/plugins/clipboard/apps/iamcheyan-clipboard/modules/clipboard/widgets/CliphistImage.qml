pragma ComponentBehavior: Bound
import QtQuick
import "../../../services"

Rectangle {
    id: root
    property string entry
    property real maxWidth: 0
    property real maxHeight: 0
    property bool active: true
    readonly property string imageSource: Cliphist.imagePath(entry)
    color: ClipboardStyle.bg
    radius: ClipboardStyle.radius
    implicitWidth: Math.max(0, Math.min(maxWidth, 380))
    implicitHeight: Math.max(0, Math.min(maxHeight, 300))
    Image {
        anchors.fill: parent
        anchors.margins: 8
        source: root.active && root.imageSource ? "file://" + root.imageSource : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
    }
}
