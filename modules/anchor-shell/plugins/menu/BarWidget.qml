import QtQuick
import Quickshell
import qs.Commons
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
        Util.execDetached("xdg-terminal-exec");
      else
        Util.execDetached(Quickshell.env("HOME") + "/.config/labwc/scripts/launcher");
    }
  }
}
