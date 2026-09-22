import QtQuick
import qs.Ui

// Keep the native Omarchy menu button contract. Because this plugin clones
// omarchy.menu, the native command is automatically routed to this plugin.
BarWidget {
  id: root
  moduleName: "iamcheyan.launcher"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectSettingsPanel() {
    if (!settingsPanelLoader.item) return
    settingsPanelLoader.item.bar = root.bar
    settingsPanelLoader.item.hostWidget = root
    settingsPanelLoader.item.anchorItem = button
    settingsPanelLoader.item.settings = root.settings
  }

  onBarChanged: injectSettingsPanel()
  onSettingsChanged: injectSettingsPanel()

  Loader {
    id: settingsPanelLoader
    active: true
    source: Qt.resolvedUrl("SettingsPanel.qml")
    visible: false
    onLoaded: {
      root.injectSettingsPanel()
      Qt.callLater(root.injectSettingsPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "Applications"
    onPressed: function (buttonCode) {
      if (!root.bar)
        return;

      if (buttonCode === Qt.RightButton) {
        if (settingsPanelLoader.item)
          settingsPanelLoader.item.toggle()
      } else {
        root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'");
      }
    }
  }
}
