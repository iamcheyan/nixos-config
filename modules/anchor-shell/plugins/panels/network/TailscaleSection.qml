import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Ui
import qs.Commons
import "../tailscale" as TailscaleComponents

// The Tailscale panel body, hosted inside the combined network popup. Keep the
// same hero, section rows, actions, and copy menu as the standalone panel.
Item {
  id: root
  property var bar: null
  property bool active: false
  signal closeRequested()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var exitNodes: service.exitNodes
  readonly property var activePhrases: [
    "Encrypting connections", "Sending secrets", "Guarding wires",
    "Braiding packets", "Polishing tunnels", "Hiding routes",
    "Sealing ports", "Sorting tailnets", "Shuffling keys", "Watching machines"
  ]
  property int phraseIndex: 1
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  implicitHeight: content.implicitHeight

  function displayName(peer) {
    return peer ? String(peer.DisplayName || peer.HostName || "Unknown") : "Unknown"
  }

  function peerOptions(peer) {
    if (!peer) return []
    var options = []
    var name = service.displayHostName(peer.HostName, peer.DNSName)
    var ips = service.filterIPv4(peer.TailscaleIPs || [])
    var ipv6 = peer.TailscaleIPv6 && peer.TailscaleIPv6.length ? String(peer.TailscaleIPv6[0] || "") : ""
    if (name) options.push({ label: name, kind: "name" })
    if (peer.DNSName) options.push({ label: service.cleanDnsName(peer.DNSName), kind: "dns" })
    if (ipv6) options.push({ label: ipv6, kind: "ipv6" })
    if (ips.length) options.push({ label: ips[0], kind: "ip" })
    return options
  }

  function copyPeer(peer, kind) {
    if (!peer) return
    if (kind === "name") service.copyPeerName(peer)
    else if (kind === "dns") service.copyPeerDnsName(peer)
    else if (kind === "ipv6") {
      var value = peer.TailscaleIPv6 && peer.TailscaleIPv6.length ? String(peer.TailscaleIPv6[0] || "") : ""
      service.copyToClipboard(value, displayName(peer) + " IPv6")
    } else service.copyPeerIp(peer)
  }

  TailscaleComponents.Service {
    id: service
    settings: ({})
  }

  onActiveChanged: if (active) service.refresh(true)

  Column {
    id: content
    width: parent.width
    spacing: Style.space(12)

    Item {
      width: parent.width
      implicitHeight: hero.implicitHeight

      PanelHero {
        id: hero
        width: parent.width
        title: service.installed ? (service.selfName || "Tailscale") : "Tailscale"
        meta: service.active ? root.heroPhraseText : "Tailscale is disconnected"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconOpacity: service.active ? 1.0 : 0.5
        iconComponent: Component {
          TailscaleComponents.TailscaleIcon {
            iconSize: Style.font.display
            color: service.active ? root.foreground : root.dim
            badgeColor: root.urgent
            crossed: !service.active && !service.needsLogin
            warning: service.needsLogin
          }
        }
        trailingControl: Component {
          ToggleSwitch {
            id: tailscaleSwitch
            visible: service.installed
            checked: service.active
            busy: service.busy
            foreground: root.foreground
            onToggled: service.toggleTailscale()
            PanelToolTip {
              visible: tailscaleSwitch.containsMouse
              text: service.active ? "Turn Tailscale off" : (service.needsLogin ? "Authorize this device" : "Turn Tailscale on")
              fontFamily: root.fontFamily
            }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: service.actionStatus !== "" || service.lastError !== ""
      width: parent.width
      text: service.actionStatus !== "" ? service.actionStatus : service.lastError
      color: service.lastError !== "" && service.actionStatus === "" ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    CursorSurface {
      visible: !service.installed
      width: parent.width
      implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
      foreground: root.foreground
      Text {
        id: missingText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(12)
        text: "Tailscale CLI is not installed or not on PATH."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }
    }

    PanelSeparator { visible: service.accountsAccessDenied || service.accounts.length > 1; foreground: root.foreground }

    Column {
      visible: service.accountsAccessDenied || service.accounts.length > 1
      width: parent.width
      spacing: Style.space(10)
      PanelSectionHeader { text: "CONNECTIONS"; foreground: root.foreground; fontFamily: root.fontFamily }

      CursorSurface {
        visible: service.accountsAccessDenied
        width: parent.width
        foreground: root.foreground
        implicitHeight: authRow.implicitHeight + Style.spacing.rowPaddingX
        RowLayout {
          id: authRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)
          Text { text: "󰒃"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.heading; Layout.alignment: Qt.AlignVCenter }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)
            Text { Layout.fillWidth: true; text: "Authorize Tailscale operator"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: "Allow this user to operate this Tailscale profile"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
          }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          enabled: !service.busy
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: service.authorizeTailscaleOperator()
        }
      }

      Repeater {
        model: service.accounts
        delegate: CursorSurface {
          required property var modelData
          width: parent.width
          foreground: root.foreground
          current: modelData.selected === true
          implicitHeight: accountText.implicitHeight + Style.spacing.xl
          Text {
            id: accountText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(8)
            text: service.accountLabel(modelData)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          MouseArea {
            anchors.fill: parent
            enabled: !service.busy && modelData.selected !== true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: service.switchAccount(modelData.id)
          }
        }
      }
    }

    PanelSeparator { visible: service.active && exitNodes.length > 0; foreground: root.foreground }

    Column {
      visible: service.active && exitNodes.length > 0
      width: parent.width
      spacing: Style.space(10)
      PanelSectionHeader { text: "EXIT NODES"; foreground: root.foreground; fontFamily: root.fontFamily }
      Repeater {
        model: root.exitNodes
        delegate: CursorSurface {
          required property var modelData
          required property int index
          width: parent.width
          foreground: root.foreground
          current: modelData.ExitNode === true
          implicitHeight: exitName.implicitHeight + Style.spacing.xl
          Text {
            id: exitName
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(8)
            text: String(modelData.DisplayName || modelData.HostName || modelData.Name || "Exit node")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: modelData.ExitNode === true
            elide: Text.ElideRight
          }
          MouseArea {
            anchors.fill: parent
            enabled: !service.busy
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: service.setExitNode(modelData)
          }
        }
      }
    }

    PanelSeparator { visible: service.installed && service.active; foreground: root.foreground }

    Column {
      visible: service.installed && service.active
      width: parent.width
      spacing: Style.space(10)
      PanelSectionHeader { text: "MACHINES"; foreground: root.foreground; fontFamily: root.fontFamily }
      Text {
        visible: service.peers.length === 0
        width: parent.width
        text: "No machines found on this tailnet."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }
      Repeater {
        model: service.peers
        delegate: CursorSurface {
          id: peerRow
          required property var modelData
          width: parent.width
          foreground: root.foreground
          implicitHeight: Math.max(peerContent.implicitHeight, copyButton.implicitHeight) + Style.spacing.rowPaddingX
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; hoverEnabled: true; cursorShape: Qt.ArrowCursor }
          RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            Text {
              text: service.osIcon(modelData.OS)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
              Layout.alignment: Qt.AlignVCenter
            }
            ColumnLayout {
              id: peerContent
              Layout.fillWidth: true
              spacing: Style.space(1)
              Text {
                Layout.fillWidth: true
                text: root.displayName(modelData)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                text: {
                  var parts = []
                  var ips = service.filterIPv4(modelData.TailscaleIPs || [])
                  if (ips.length) parts.push(ips[0])
                  if (modelData.DNSName) parts.push(String(modelData.DNSName))
                  return parts.join(" · ")
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            PanelActionButton {
              visible: service.canSendFiles(peerRow.modelData)
              iconText: "󰒊"
              tooltipText: "Send files"
              foreground: root.foreground
              fontFamily: root.fontFamily
              Layout.alignment: Qt.AlignVCenter
              onClicked: {
                service.sendFile(peerRow.modelData)
                root.closeRequested()
              }
            }
            PanelActionButton {
              id: copyButton
              iconText: "󰆏"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.peerOptions(peerRow.modelData).length > 0
              Layout.alignment: Qt.AlignVCenter
              onClicked: copyPopup.open()
            }
            Popup {
              id: copyPopup
              x: copyButton.x + copyButton.width - width
              y: copyButton.y + copyButton.height + Style.space(4)
              width: Style.space(280)
              padding: 0
              modal: false
              focus: true
              closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
              background: BorderSurface { color: Color.background; borderSpec: Border.flat(root.dim, 1); radius: Style.cornerRadius }
              contentItem: Column {
                width: parent.width
                Repeater {
                  model: root.peerOptions(peerRow.modelData)
                  delegate: CursorSurface {
                    required property var modelData
                    width: parent.width
                    foreground: root.foreground
                    implicitHeight: Style.space(48)
                    Text {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(12)
                      anchors.rightMargin: Style.space(12)
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { root.copyPeer(peerRow.modelData, modelData.kind); copyPopup.close() }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    interval: 2800
    running: root.active && service.active
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }
}
