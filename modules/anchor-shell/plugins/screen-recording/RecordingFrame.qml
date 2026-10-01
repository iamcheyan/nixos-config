import QtQuick

Item {
  id: root

  required property real regionX
  required property real regionY
  required property real regionWidth
  required property real regionHeight
  required property real mouseX
  required property real mouseY
  property color color: "#e5e5e5"
  property color accentColor: "#e53935"
  property bool recordingActive: false
  property bool showAimLines: true
  property bool showSize: true

  readonly property color effectiveBorderColor: root.recordingActive ? root.accentColor : root.color
  readonly property bool hasRegion: root.regionWidth > 1 && root.regionHeight > 1

  visible: root.hasRegion

  Rectangle {
    id: selectionBorder
    z: 9
    readonly property real inset: root.recordingActive ? -border.width / 2 : 0
    x: Math.round(root.regionX) + inset
    y: Math.round(root.regionY) + inset
    width: Math.round(root.regionWidth) - inset * 2
    height: Math.round(root.regionHeight) - inset * 2
    color: "transparent"
    border.color: root.effectiveBorderColor
    border.width: 2
    radius: 4
    opacity: 0.9
  }

  Repeater {
    model: root.recordingActive ? 4 : 0
    Rectangle {
      required property int index
      readonly property real cx: (index === 0 || index === 2) ? root.regionX : root.regionX + root.regionWidth
      readonly property real cy: (index === 0 || index === 1) ? root.regionY : root.regionY + root.regionHeight
      x: cx - 7
      y: cy - 7
      width: 14
      height: 14
      radius: 7
      color: root.accentColor
      border.width: 1.5
      border.color: Qt.rgba(1, 1, 1, 0.6)
      z: 11
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.25; duration: 700 }
        NumberAnimation { from: 0.25; to: 1; duration: 700 }
      }
    }
  }

  Text {
    z: 2
    visible: root.showSize
    anchors.top: selectionBorder.bottom
    anchors.right: selectionBorder.right
    anchors.margins: 8
    color: root.effectiveBorderColor
    text: Math.round(root.regionWidth) + " × " + Math.round(root.regionHeight)
    font.pixelSize: 13
    font.weight: Font.DemiBold
  }

  Rectangle {
    visible: root.showAimLines && !root.recordingActive
    opacity: 0.2
    z: 2
    x: root.mouseX
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: root.color
  }

  Rectangle {
    visible: root.showAimLines && !root.recordingActive
    opacity: 0.2
    z: 2
    y: root.mouseY
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: root.color
  }
}
