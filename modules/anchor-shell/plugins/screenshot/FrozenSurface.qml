import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: surface
  required property var host
  required property var modelData

  screen: surface.modelData
  color: "#111111"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "anchor-frozen-screenshot"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: surface.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors { left: true; right: true; top: true; bottom: true }
  visible: host.selecting

  property string outputName: String(modelData && modelData.name ? modelData.name : "")
  property bool dragging: false
  property real startX: 0
  property real startY: 0
  property real endX: 0
  property real endY: 0
  property bool squareModifierHeld: false
  readonly property real squareSide: {
    if (!squareModifierHeld) return 0
    var dx = endX - startX
    var dy = endY - startY
    var maxX = dx < 0 ? startX : width - startX
    var maxY = dy < 0 ? startY : height - startY
    return Math.max(0, Math.min(Math.max(Math.abs(dx), Math.abs(dy)), maxX, maxY))
  }
  readonly property real selectionEndX: squareModifierHeld
    ? startX + (endX < startX ? -squareSide : squareSide) : endX
  readonly property real selectionEndY: squareModifierHeld
    ? startY + (endY < startY ? -squareSide : squareSide) : endY
  readonly property real selectX: Math.min(startX, selectionEndX)
  readonly property real selectY: Math.min(startY, selectionEndY)
  readonly property real selectW: Math.abs(selectionEndX - startX)
  readonly property real selectH: Math.abs(selectionEndY - startY)

  Image {
    anchors.fill: parent
    id: snapshotImage
    source: surface.visible ? "file://" + host.capturePath(surface.outputName) + "?v=" + host.requestId : ""
    fillMode: Image.Stretch
    cache: false
  }

  Rectangle {
    anchors.fill: parent
    visible: !surface.dragging
    color: "#66000000"
  }

  Rectangle {
    visible: surface.dragging
    x: 0; y: 0
    width: parent.width; height: surface.selectY
    color: "#66000000"
  }
  Rectangle {
    visible: surface.dragging
    x: 0; y: surface.selectY + surface.selectH
    width: parent.width; height: Math.max(0, parent.height - y)
    color: "#66000000"
  }
  Rectangle {
    visible: surface.dragging
    x: 0; y: surface.selectY
    width: surface.selectX; height: surface.selectH
    color: "#66000000"
  }
  Rectangle {
    visible: surface.dragging
    x: surface.selectX + surface.selectW; y: surface.selectY
    width: Math.max(0, parent.width - x); height: surface.selectH
    color: "#66000000"
  }

  Rectangle {
    visible: surface.dragging && surface.selectW > 2 && surface.selectH > 2
    x: surface.selectX; y: surface.selectY
    width: surface.selectW; height: surface.selectH
    color: "#12000000"
    border.color: "#ffffff"
    border.width: 2
  }

  Rectangle {
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: 24
    width: hint.implicitWidth + 28
    height: 38
    radius: 8
    color: "#d91a1a1a"
    border.color: "#55ffffff"

    Text {
      id: hint
      anchors.centerIn: parent
      text: "拖动选择截图区域  ·  Shift 正方形  ·  Esc 取消"
      color: "white"
      font.pixelSize: 14
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.CrossCursor
    onPressed: function(mouse) {
      surface.dragging = true
      surface.startX = mouse.x; surface.startY = mouse.y
      surface.endX = mouse.x; surface.endY = mouse.y
    }
    onPositionChanged: function(mouse) {
      if (surface.dragging) { surface.endX = mouse.x; surface.endY = mouse.y }
    }
    onReleased: function(mouse) {
      surface.endX = mouse.x; surface.endY = mouse.y
      var cropX = surface.selectX
      var cropY = surface.selectY
      var cropWidth = surface.selectW
      var cropHeight = surface.selectH
      surface.dragging = false
      surface.squareModifierHeld = false
      if (cropWidth > 2 && cropHeight > 2) {
        var scale = snapshotImage.implicitWidth > 0 ? snapshotImage.implicitWidth / surface.width : 1
        host.copyRegion(surface.outputName, cropX, cropY, cropWidth, cropHeight, scale)
      } else host.finish()
    }
    onCanceled: host.finish()
  }

  Item {
    anchors.fill: parent
    focus: surface.visible
    Keys.onEscapePressed: host.finish()
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Shift) {
        surface.squareModifierHeld = true
        event.accepted = true
      }
    }
    Keys.onReleased: function(event) {
      if (event.key === Qt.Key_Shift) {
        surface.squareModifierHeld = false
        event.accepted = true
      }
    }
  }
}
