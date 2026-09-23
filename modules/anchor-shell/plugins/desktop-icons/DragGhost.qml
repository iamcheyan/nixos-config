import QtQuick
import qs.Commons

Item {
  id: ghost

  required property var host
  required property var surface

  z: 40
  width: host.cellW
  height: host.cellH
  enabled: false
  visible: host.dragId !== "" && host.dragEntry
           && host.dragHoverScreen === surface.screenName
           && host.dragOriginScreen !== surface.screenName
  x: host.dragSceneX - surface.modelData.x - host.dragGrabX
  y: host.dragSceneY - surface.modelData.y - host.dragGrabY
  opacity: 0.96

  Column {
    anchors.fill: parent
    anchors.margins: 6
    spacing: 4

    Item {
      width: host.iconSize
      height: host.iconSize
      anchors.horizontalCenter: parent.horizontalCenter

      Image {
        anchors.fill: parent
        source: host.iconSource(host.dragEntry)
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: false
        smooth: true
        sourceSize.width: host.iconIsRaster(source) ? host.iconPixels : 0
        sourceSize.height: host.iconIsRaster(source) ? host.iconPixels : 0
      }
    }

    Text {
      width: parent.width
      text: host.plainText(host.dragEntry ? host.dragEntry.name : "")
      textFormat: Text.PlainText
      color: "white"
      style: Text.Outline
      styleColor: "#cc000000"
      font.pixelSize: 12
      font.family: Style.fontFamily
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      maximumLineCount: 2
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
