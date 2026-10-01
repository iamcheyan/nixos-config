pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: panel

  required property var modelData
  required property var host

  screen: modelData
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "selection"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: panel.ownsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  anchors {
    left: true
    right: true
    top: true
    bottom: true
  }

  readonly property string screenName: String(modelData && modelData.name ? modelData.name : "default")
  readonly property string session: host ? String(host.session || "idle") : "idle"
  readonly property bool isTarget: host && (host.targetOutput === "" || host.targetOutput === panel.screenName)
  readonly property bool overlayOpen: panel.session !== "idle" && panel.isTarget
  readonly property bool selecting: panel.session === "selecting"
  readonly property bool countdowning: panel.session === "countdown" || panel.session === "starting"
  readonly property bool live: panel.session === "recording" || panel.session === "paused"
  readonly property bool ownsKeyboard: panel.overlayOpen && (panel.selecting || panel.countdowning)
  readonly property color overlayColor: Qt.rgba(0, 0, 0, 0.5)
  readonly property color recordingAccent: "#e53935"
  readonly property color brightText: "#f4f4f4"
  readonly property color brightSecondary: "#b8b8b8"
  readonly property color selectionBorder: "#e5e5e5"

  property bool dragging: false
  property bool shiftPressed: false
  property real dragStartX: 0
  property real dragStartY: 0
  property real draggingX: 0
  property real draggingY: 0

  readonly property real liveWidth: {
    var dx = panel.draggingX - panel.dragStartX
    var dy = panel.draggingY - panel.dragStartY
    if (panel.shiftPressed) return Math.max(Math.abs(dx), Math.abs(dy))
    return Math.abs(dx)
  }
  readonly property real liveHeight: {
    var dx = panel.draggingX - panel.dragStartX
    var dy = panel.draggingY - panel.dragStartY
    if (panel.shiftPressed) return Math.max(Math.abs(dx), Math.abs(dy))
    return Math.abs(dy)
  }
  readonly property real liveX: {
    var dx = panel.draggingX - panel.dragStartX
    if (panel.shiftPressed)
      return dx >= 0 ? panel.dragStartX : panel.dragStartX - panel.liveWidth
    return Math.min(panel.dragStartX, panel.draggingX)
  }
  readonly property real liveY: {
    var dy = panel.draggingY - panel.dragStartY
    if (panel.shiftPressed)
      return dy >= 0 ? panel.dragStartY : panel.dragStartY - panel.liveHeight
    return Math.min(panel.dragStartY, panel.draggingY)
  }

  readonly property real regionX: panel.selecting
    ? (panel.dragging ? panel.liveX : (host && host.targetOutput === panel.screenName ? host.regionX : 0))
    : (host ? host.regionX : 0)
  readonly property real regionY: panel.selecting
    ? (panel.dragging ? panel.liveY : (host && host.targetOutput === panel.screenName ? host.regionY : 0))
    : (host ? host.regionY : 0)
  readonly property real regionW: panel.selecting
    ? (panel.dragging ? panel.liveWidth : (host && host.targetOutput === panel.screenName ? host.regionW : 0))
    : (host ? host.regionW : 0)
  readonly property real regionH: panel.selecting
    ? (panel.dragging ? panel.liveHeight : (host && host.targetOutput === panel.screenName ? host.regionH : 0))
    : (host ? host.regionH : 0)

  visible: panel.overlayOpen
  mask: Region {
    item: {
      if (panel.selecting) return selectMouse
      if (panel.live) return recordingControls
      return noInput
    }
  }

  Item { id: noInput; width: 0; height: 0 }

  onVisibleChanged: if (panel.visible && panel.ownsKeyboard) keyScope.forceActiveFocus()
  onOwnsKeyboardChanged: if (panel.ownsKeyboard) keyScope.forceActiveFocus()

  Item {
    id: keyScope
    anchors.fill: parent
    visible: panel.overlayOpen
    focus: panel.ownsKeyboard

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (panel.selecting || panel.countdowning) {
          if (host) host.cancel()
          event.accepted = true
        }
      } else if (event.key === Qt.Key_Shift) {
        panel.shiftPressed = true
      }
    }
    Keys.onReleased: function(event) {
      if (event.key === Qt.Key_Shift) panel.shiftPressed = false
    }

    Item {
      id: outsideMask
      anchors.fill: parent
      visible: panel.regionW > 1 && panel.regionH > 1

      Rectangle {
        x: 0; y: 0
        width: parent.width
        height: Math.max(0, panel.regionY)
        color: panel.overlayColor
      }
      Rectangle {
        x: 0
        y: Math.min(parent.height, panel.regionY + panel.regionH)
        width: parent.width
        height: Math.max(0, parent.height - y)
        color: panel.overlayColor
      }
      Rectangle {
        x: 0
        y: Math.max(0, panel.regionY)
        width: Math.max(0, panel.regionX)
        height: Math.max(0, Math.min(parent.height, panel.regionY + panel.regionH) - y)
        color: panel.overlayColor
      }
      Rectangle {
        x: Math.min(parent.width, panel.regionX + panel.regionW)
        y: Math.max(0, panel.regionY)
        width: Math.max(0, parent.width - x)
        height: Math.max(0, Math.min(parent.height, panel.regionY + panel.regionH) - y)
        color: panel.overlayColor
      }
    }

    Rectangle {
      anchors.fill: parent
      visible: panel.selecting && !(panel.dragging || (host && host.targetOutput === panel.screenName && host.regionW > 1))
      color: panel.overlayColor
    }

    RecordingFrame {
      anchors.fill: parent
      regionX: panel.regionX
      regionY: panel.regionY
      regionWidth: panel.regionW
      regionHeight: panel.regionH
      mouseX: selectMouse.mouseX
      mouseY: selectMouse.mouseY
      color: panel.selectionBorder
      accentColor: panel.recordingAccent
      recordingActive: panel.live
      showAimLines: panel.selecting && panel.dragging
      showSize: panel.selecting || panel.countdowning
    }

    MouseArea {
      id: selectMouse
      anchors.fill: parent
      hoverEnabled: panel.selecting
      cursorShape: panel.selecting ? Qt.CrossCursor : Qt.ArrowCursor
      acceptedButtons: panel.selecting ? Qt.LeftButton : Qt.NoButton
      enabled: panel.selecting
      onPressed: function(mouse) {
        panel.shiftPressed = (mouse.modifiers & Qt.ShiftModifier) !== 0
        panel.dragStartX = mouse.x
        panel.dragStartY = mouse.y
        panel.draggingX = mouse.x
        panel.draggingY = mouse.y
        panel.dragging = true
      }
      onPositionChanged: function(mouse) {
        if (!panel.dragging) return
        panel.shiftPressed = (mouse.modifiers & Qt.ShiftModifier) !== 0
        panel.draggingX = mouse.x
        panel.draggingY = mouse.y
      }
      onReleased: function(mouse) {
        if (!panel.dragging) return
        panel.shiftPressed = (mouse.modifiers & Qt.ShiftModifier) !== 0
        panel.draggingX = mouse.x
        panel.draggingY = mouse.y
        panel.dragging = false
        if (panel.liveWidth < 8 || panel.liveHeight < 8) return
        if (host) host.confirmRegion(panel.screenName, panel.liveX, panel.liveY, panel.liveWidth, panel.liveHeight)
      }
    }

    Item {
      visible: panel.countdowning
      x: panel.regionX + Math.max(0, (panel.regionW - 180) / 2)
      y: panel.regionY + Math.max(0, (panel.regionH - 180) / 2)
      width: 180
      height: 180

      Rectangle {
        anchors.fill: parent
        radius: 24
        color: Qt.rgba(0, 0, 0, 0.55)
        border.color: panel.selectionBorder
        border.width: 2

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 6

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: host && host.countdown > 0 ? String(host.countdown) : "…"
            color: panel.brightText
            font.pixelSize: 72
            font.weight: Font.Black
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Starting recording…"
            color: panel.brightSecondary
            font.pixelSize: 14
          }
        }
      }
    }

    Item {
      id: recordingControls
      visible: panel.live
      x: {
        var barW = width
        var rightEdge = panel.regionX + panel.regionW
        var clampedX = Math.max(0, rightEdge - barW)
        return Math.min(clampedX, panel.width - barW)
      }
      y: {
        var barH = height
        var yBelow = panel.regionY + panel.regionH + 12
        if (yBelow + barH <= panel.height) return yBelow
        var yAbove = panel.regionY - 12 - barH
        if (yAbove >= 0) return yAbove
        return Math.max(0, panel.height - barH - 12)
      }
      width: recordBar.implicitWidth
      height: recordBar.implicitHeight

      Row {
        id: recordBar
        spacing: 8

        Rectangle {
          width: Math.max(110, recTimerText.implicitWidth + 36)
          height: 40
          radius: 8
          color: Qt.rgba(0.12, 0.12, 0.12, 0.92)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.18)

          Row {
            anchors.centerIn: parent
            spacing: 8

            Rectangle {
              width: 12
              height: 12
              radius: 6
              anchors.verticalCenter: parent.verticalCenter
              color: host && host.paused ? "#f2c94c" : panel.recordingAccent
              SequentialAnimation on opacity {
                running: panel.live && !(host && host.paused)
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.25; duration: 700 }
                NumberAnimation { from: 0.25; to: 1; duration: 700 }
              }
            }

            Text {
              id: recTimerText
              anchors.verticalCenter: parent.verticalCenter
              text: host ? host.elapsedText : "0:00"
              color: panel.brightText
              font.pixelSize: 16
              font.weight: Font.DemiBold
            }
          }
        }

        Rectangle {
          width: 40
          height: 40
          radius: 8
          color: pauseMouse.containsMouse ? Qt.rgba(0.22, 0.22, 0.22, 0.95) : Qt.rgba(0.12, 0.12, 0.12, 0.92)
          border.width: 1
          border.color: pauseMouse.containsMouse ? panel.recordingAccent : Qt.rgba(1, 1, 1, 0.18)

          Text {
            anchors.centerIn: parent
            text: host && host.paused ? "󰐊" : "󰏤"
            color: pauseMouse.containsMouse ? panel.recordingAccent : panel.brightText
            font.pixelSize: 18
          }

          MouseArea {
            id: pauseMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (host) host.togglePause()
          }
        }

        Rectangle {
          width: 40
          height: 40
          radius: 8
          color: stopMouse.containsMouse ? Qt.rgba(0.22, 0.22, 0.22, 0.95) : Qt.rgba(0.12, 0.12, 0.12, 0.92)
          border.width: 1
          border.color: stopMouse.containsMouse ? panel.recordingAccent : Qt.rgba(1, 1, 1, 0.18)

          Text {
            anchors.centerIn: parent
            text: "󰓛"
            color: stopMouse.containsMouse ? panel.recordingAccent : panel.brightText
            font.pixelSize: 18
          }

          MouseArea {
            id: stopMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (host) host.stop()
          }
        }
      }
    }
  }
}
