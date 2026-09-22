import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.power"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    if ("bar" in panel) panel.bar = root.bar
    if ("settings" in panel) panel.settings = root.settings
    if ("anchorItem" in panel) panel.anchorItem = button
    if ("hostWidget" in panel) panel.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Use the same Nerd Font power glyph as the session menu. Unlike the
    // UPower battery glyph, this is always present on desktop machines.
    text: "󰐥"
    slotSize: Style.bar.iconSlot
    tooltipText: "Power"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton && panelLoader.item) {
        panelLoader.item.togglePercentage()
      } else {
        root.toggle()
      }
    }
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
}
