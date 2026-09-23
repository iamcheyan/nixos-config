import QtQuick
import QtQuick.Window
import Quickshell
import qs.Ui

// Applications-only launcher button for Anchor Shell.
BarWidget {
  id: root
  moduleName: "launcher"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "Applications"
    onPressed: function (buttonCode) {
      if (!root.bar || buttonCode !== Qt.LeftButton || !root.bar.shell)
        return
      // Each bar instance lives on its own output. Prefer the Quickshell
      // window's screen, then the Qt window's screen, so the launcher opens
      // on the monitor that was clicked instead of always the primary one.
      var barScreen = (root.QsWindow && root.QsWindow.window && root.QsWindow.window.screen)
        ? root.QsWindow.window.screen
        : (Window.window && Window.window.screen ? Window.window.screen : null)
      var screenName = barScreen ? String(barScreen.name || "") : ""
      root.bar.shell.toggle("launcher", JSON.stringify({
        menu: "root",
        screen: screenName
      }))
    }
  }
}
