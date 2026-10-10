import QtQuick
import Quickshell
import Quickshell.Io
import Flux 1.0 as FluxUi
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "flux"
  ipcTarget: "flux"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property string savedTab: "overview"
  property string savedDevice: ""

  readonly property var flux: root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor("flux") : null
  readonly property bool linked: {
    if (!flux || !flux.backend || !flux.backend.connected) return false
    var devices = flux.backend.devices || []
    for (var i = 0; i < devices.length; i++)
      if (devices[i].paired && devices[i].online) return true
    return false
  }

  function inject() {
    if (panelCard) {
      panelCard.bar = root.bar
      panelCard.anchorItem = root.anchorItem
    }
  }
  function close() { root.controller.hide() }
  function toggle() { root.controller.toggle() }
  onBarChanged: inject()
  onAnchorItemChanged: inject()
  onFluxChanged: if (flux) flux.backend.retryNow()

  PopupCard {
    id: panelCard
    owner: root
    bar: root.bar
    anchorItem: root.anchorItem
    open: root.opened
    margin: 8
    contentWidth: {
      var screen = root.anchorItem && root.anchorItem.QsWindow && root.anchorItem.QsWindow.window
        ? root.anchorItem.QsWindow.window.screen : null
      return Math.min(1180, screen ? screen.width - 24 : 1180)
    }
    contentHeight: {
      var screen = root.anchorItem && root.anchorItem.QsWindow && root.anchorItem.QsWindow.window
        ? root.anchorItem.QsWindow.window.screen : null
      return Math.min(760, screen ? screen.height - 48 : 760)
    }

    FluxUi.FluxView {
      anchors.fill: parent
      backend: root.flux ? root.flux.backend : null
      themeText: root.flux ? root.flux.themeText : ""
      tab: root.savedTab
      selectedId: root.savedDevice
      onTabChanged: root.savedTab = tab
      onSelectedIdChanged: root.savedDevice = selectedId
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.opened
    useActiveColor: true
    activeColor: root.linked ? Color.accent : Color.urgent
    slotSize: Style.bar.iconSlot
    opticalSize: Style.bar.iconCanvas
    iconComponent: Component {
      FluxUi.FluxMark {
        size: 14
        fg: button.foreground
        accent: root.linked ? Color.accent : button.foreground
      }
    }
    tooltipText: root.linked ? "Flux · phone connected" : "Flux · phone link"
    onPressed: function(mouseButton) { root.toggle() }
  }

  Component.onCompleted: {
    root.anchorItem = button
    root.hostWidget = button
    inject()
  }
}
