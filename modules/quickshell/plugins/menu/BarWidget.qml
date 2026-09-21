import QtQuick
import qs.Ui

// Applications launcher button for the Labwc bar.
BarWidget {
  id: root
  moduleName: "omarchy.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "Applications"
    horizontalMargin: 10
    onPressed: function (button) {
      if (!root.bar)
        return;
      if (button === Qt.RightButton)
        root.bar.run("xdg-terminal-exec");
      else
        root.bar.run("$HOME/.config/labwc/scripts/launcher");
    }
  }
}
