import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property string modeFilePath: (Quickshell.env("ANCHOR_SHELL_CONFIG_DIR")
    || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/anchor-shell"))
    + "/mode"
  property string storedMode: ""

  FileView {
    id: modeFileWatcher
    path: root.modeFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.storedMode = text().trim()
    onFileChanged: reload()
    onLoadFailed: root.storedMode = ""
  }

  readonly property string shellRootPath: root.bar && root.bar.shell ? root.bar.shell.shellPath : (Quickshell.env("QUICKSHELL_ROOT") || "")
  readonly property bool isDevMode: storedMode === "dev" || (shellRootPath !== "" && !shellRootPath.startsWith("/nix/store"))

  active: isDevMode
  activeText: "󰅩"
  inactiveText: ""
  activeTooltipText: "Developer Mode (Click for actions)"
  useActiveColor: true
  activeColor: "#eab308"

  function exitDevModeAndDeploy() {
    var cmd = "xdg-terminal-exec --app-id=org.omarchy.terminal --title='Anchor Shell Deploy' /home/tetsuya/nixos-config/modules/anchor-shell/bin/anchor-shell-deploy"
    Util.execDetached(cmd)
  }

  function reloadDevMode() {
    Util.execDetached("quickshell-mode dev")
  }

  function exitDevModeOnly() {
    Util.execDetached("quickshell-mode nix")
  }

  function toggle() {
    devMenu.open = !devMenu.open
  }

  onPressed: function() { root.toggle() }

  PopupCard {
    id: devMenu
    anchorItem: root
    bar: root.bar
    owner: root
    open: false
    contentWidth: devMenu.fittedContentWidth(Style.space(270))
    contentHeight: devMenu.fittedContentHeight(devMenuCol.implicitHeight)

    Column {
      id: devMenuCol
      width: parent.width
      spacing: Style.space(6)

      Row {
        spacing: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right

        Text {
          text: "󰅩"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          color: "#eab308"
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            text: "Developer Mode"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            color: Color.popups.text
          }

          Text {
            text: "Running from workspace"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Util.alpha(Color.popups.text, 0.6)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(Color.popups.text, 0.12)
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰏔"
        text: "Exit Dev Mode & Deploy"
        tooltipText: "Stage changes, run nixos-rebuild switch, and return to store mode"
        onClicked: {
          devMenu.open = false
          root.exitDevModeAndDeploy()
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰑐"
        text: "Reload Shell (Dev)"
        tooltipText: "Restart Quickshell reloading current workspace files"
        onClicked: {
          devMenu.open = false
          root.reloadDevMode()
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰈆"
        text: "Exit Dev Mode (No Deploy)"
        tooltipText: "Return to production store mode without rebuilding"
        onClicked: {
          devMenu.open = false
          root.exitDevModeOnly()
        }
      }
    }
  }
}
