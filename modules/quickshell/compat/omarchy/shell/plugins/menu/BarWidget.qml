import QtQuick
import qs.Ui

// Replaces upstream's shell/plugins/menu/BarWidget.qml so the menu button
// wears the NixOS snowflake instead of the Omarchy mark. Everything else --
// the click targets, the sizing, the right-click-opens-a-terminal behaviour --
// is upstream's and is kept verbatim.
//
// The mark is a PNG, not the scalable nix-snowflake.svg: nixpkgs' quickshell
// ships no Qt image-format plugins at all, and SVG support is one of them, so
// an <Image source="...svg"> renders nothing. PNG is decoded by Qt itself.
BarWidget {
  id: root
  moduleName: "omarchy.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The glyph stays so the button keeps upstream's width, hit area and
    // hasVisualContent; only its label is hidden, with the image drawn over
    // the same centre.
    text: ""
    fontFamily: "omarchy"
    labelVisible: false
    horizontalMargin: 7.5
    onPressed: function (button) {
      if (!root.bar)
        return;
      if (button === Qt.RightButton)
        root.bar.run("xdg-terminal-exec");
      else
        root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'");
    }

    Image {
      id: snowflake
      anchors.centerIn: parent
      source: "file:///nix/store/hgq5nqzdz4c5p6ys9hc0i837vw0l9055-nixos-icons-0-unstable-2025-06-28/share/icons/hicolor/256x256/apps/nix-snowflake.png"
      // Sized off the bar's own font metric so it tracks bar scaling rather
      // than being pinned to a pixel count.
      readonly property int side: Math.round(button.fontSize * 1.3)
      sourceSize.width: side
      sourceSize.height: side
      width: side
      height: side
      smooth: true
      mipmap: true
      opacity: button.dimmed ? 0.45 : 1
    }
  }
}
