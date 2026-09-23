import QtQuick
import qs.Commons

Rectangle {
  id: trustBox

  required property var host
  required property var panel

  visible: {
    var item = host.pendingTrust
    if (!item)
      return false
    if (host.pendingTrustScreen && host.pendingTrustScreen !== panel.screenName)
      return false
    return true
  }
  z: 21
  width: Math.min(360, Math.max(280, panel.width - 48))
  height: trustCol.implicitHeight + 24
  radius: 8
  color: Color.popups.background
  border.width: 1
  border.color: Color.popups.border
  x: {
    var p = panel.trustIconPos()
    if (!p)
      return Math.max(8, Math.round(panel.width / 2 - width / 2))
    return Math.min(Math.max(8, Math.round(p.x + host.cellW / 2 - width / 2)),
                    Math.max(8, panel.width - width - 8))
  }
  y: {
    var p = panel.trustIconPos()
    if (!p)
      return Math.max(8, Math.round(panel.height / 2 - height / 2))
    var above = p.y - height - 8
    if (above >= 8)
      return above
    return p.y + host.cellH + 8
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  Column {
    id: trustCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 12
    spacing: 10

    Text {
      width: parent.width
      text: "Untrusted launcher"
      textFormat: Text.PlainText
      color: Color.popups.text
      font.pixelSize: 15
      font.bold: true
      font.family: Style.fontFamily
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      text: {
        var item = host.pendingTrust
        var label = item ? (item.id || item.name || "this shortcut") : "this shortcut"
        return "\"" + host.plainText(label, 80) + "\" is not marked as trusted. Opening it will run commands from the file."
      }
      textFormat: Text.PlainText
      color: Color.popups.text
      font.pixelSize: 13
      font.family: Style.fontFamily
      wrapMode: Text.WordWrap
    }

    Row {
      anchors.right: parent.right
      spacing: 8

      Rectangle {
        width: cancelLabel.implicitWidth + 20
        height: 28
        radius: 4
        color: cancelMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : "transparent"
        border.width: 1
        border.color: Color.popups.border

        Text {
          id: cancelLabel
          anchors.centerIn: parent
          text: "Cancel"
          textFormat: Text.PlainText
          color: Color.popups.text
          font.pixelSize: 13
          font.family: Style.fontFamily
        }

        MouseArea {
          id: cancelMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: host.clearTrustPrompt()
        }
      }

      Rectangle {
        width: trustLabel.implicitWidth + 20
        height: 28
        radius: 4
        color: trustMouse.containsMouse ? Util.alpha(Color.popups.text, 0.12) : Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        border.color: Color.popups.border

        Text {
          id: trustLabel
          anchors.centerIn: parent
          text: "Trust and Open"
          textFormat: Text.PlainText
          color: Color.popups.text
          font.pixelSize: 13
          font.family: Style.fontFamily
        }

        MouseArea {
          id: trustMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: host.trustAndOpen(host.pendingTrust)
        }
      }
    }
  }
  }
