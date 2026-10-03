import QtQuick
import qs.Commons
import "Model.js" as Model

// Compact, draggable view of the connected outputs. Coordinates are Labwc's
// logical output positions; the backend remains wlr-randr via the shared
// Omarchy compatibility command.
Item {
  id: root

  required property var displays
  required property string selectedName
  required property color foreground
  required property string fontFamily

  signal positionRequested(string name, int x, int y)

  readonly property var enabledDisplays: (displays || []).filter(function(d) { return d.enabled !== false })
  readonly property var bounds: computeBounds()
  readonly property real stageMargin: Style.space(10)
  readonly property real stageWidth: width - stageMargin * 2
  readonly property real stageHeight: height - stageMargin * 2
  readonly property real fitScale: Math.min(
    stageWidth / Math.max(1, bounds.width),
    stageHeight / Math.max(1, bounds.height))

  implicitHeight: Style.space(180)

  function sizeOf(display) {
    var width = Number(display.width || 1)
    var height = Number(display.height || 1)
    var transform = String(display.transform || "normal")
    if (transform === "90" || transform === "270"
        || transform === "flipped-90" || transform === "flipped-270") {
      var swap = width; width = height; height = swap
    }
    var scale = Math.max(0.25, Number(display.scale || 1))
    return { width: width / scale, height: height / scale }
  }

  function computeBounds() {
    var minX = 0, minY = 0, maxX = 1, maxY = 1
    if (!enabledDisplays.length) return { minX: 0, minY: 0, width: 1, height: 1 }
    minX = Infinity; minY = Infinity; maxX = -Infinity; maxY = -Infinity
    for (var i = 0; i < enabledDisplays.length; i++) {
      var display = enabledDisplays[i]
      var size = sizeOf(display)
      var x = Number(display.x || 0), y = Number(display.y || 0)
      minX = Math.min(minX, x); minY = Math.min(minY, y)
      maxX = Math.max(maxX, x + size.width); maxY = Math.max(maxY, y + size.height)
    }
    return { minX: minX, minY: minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) }
  }

  function overlaps(a, b) {
    return a.x < b.x + b.width && a.x + a.width > b.x
      && a.y < b.y + b.height && a.y + a.height > b.y
  }

  function arrangePosition(name, requestedX, requestedY) {
    var moved = null
    for (var i = 0; i < enabledDisplays.length; i++) {
      if (enabledDisplays[i].name === name) { moved = enabledDisplays[i]; break }
    }
    if (!moved) return { x: requestedX, y: requestedY }
    var movedSize = sizeOf(moved)
    var raw = { x: Math.round(requestedX), y: Math.round(requestedY), width: movedSize.width, height: movedSize.height }
    var others = []
    for (var j = 0; j < enabledDisplays.length; j++) {
      var other = enabledDisplays[j]
      if (other.name === name) continue
      var otherSize = sizeOf(other)
      others.push({ x: Number(other.x || 0), y: Number(other.y || 0), width: otherSize.width, height: otherSize.height })
    }
    var collides = false
    for (var k = 0; k < others.length; k++) if (overlaps(raw, others[k])) collides = true
    if (!others.length) return { x: raw.x, y: raw.y }

    // If the pointer lands on another display, choose its nearest clean edge
    // and align the screens by start, centre, or end as OmniDisplay does.
    var best = null, bestDistance = Infinity
    for (var n = 0; n < others.length; n++) {
      var ref = others[n]
      var ys = [ref.y, ref.y + ref.height - movedSize.height,
        ref.y + (ref.height - movedSize.height) / 2, raw.y]
      var xs = [ref.x, ref.x + ref.width - movedSize.width,
        ref.x + (ref.width - movedSize.width) / 2, raw.x]
      var candidates = []
      for (var yi = 0; yi < ys.length; yi++) {
        candidates.push({ x: ref.x + ref.width, y: Math.round(ys[yi]) })
        candidates.push({ x: ref.x - movedSize.width, y: Math.round(ys[yi]) })
      }
      for (var xi = 0; xi < xs.length; xi++) {
        candidates.push({ x: Math.round(xs[xi]), y: ref.y + ref.height })
        candidates.push({ x: Math.round(xs[xi]), y: ref.y - movedSize.height })
      }
      for (var c = 0; c < candidates.length; c++) {
        var candidate = { x: candidates[c].x, y: candidates[c].y, width: movedSize.width, height: movedSize.height }
        var blocked = false
        for (var q = 0; q < others.length; q++) if (overlaps(candidate, others[q])) blocked = true
        if (blocked) continue
        var dx = candidate.x - raw.x, dy = candidate.y - raw.y
        var distance = dx * dx + dy * dy
        if (distance < bestDistance) { bestDistance = distance; best = candidate }
      }
    }
    if (best && (collides || bestDistance <= 72 * 72)) return { x: best.x, y: best.y }
    if (!collides) return { x: raw.x, y: raw.y }
    return { x: Number(moved.x || 0), y: Number(moved.y || 0) }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.darker(root.foreground, 3.1)
    border.width: Style.normalBorderWidth
    border.color: Qt.darker(root.foreground, 2.3)
  }

  Item {
    id: stage
    anchors.fill: parent
    anchors.margins: root.stageMargin
    clip: true

    Repeater {
      model: root.enabledDisplays

      delegate: Rectangle {
        id: displayCard
        required property var modelData
        required property int index

        readonly property var logical: root.sizeOf(modelData)
        readonly property bool selected: modelData.name === root.selectedName
        readonly property string summary: Model.displaySummary(modelData)

        function layoutX() {
          return (Number(modelData.x || 0) - root.bounds.minX) * root.fitScale
            + (stage.width - root.bounds.width * root.fitScale) / 2
        }
        function layoutY() {
          return (Number(modelData.y || 0) - root.bounds.minY) * root.fitScale
            + (stage.height - root.bounds.height * root.fitScale) / 2
        }
        function restoreLayoutBinding() {
          displayCard.x = Qt.binding(function() { return displayCard.layoutX() })
          displayCard.y = Qt.binding(function() { return displayCard.layoutY() })
        }
        property real pressX: 0
        property real pressY: 0

        // At tiny scales keep the name legible while preserving the relative
        // arrangement well enough to understand which screen is beside which.
        width: Math.max(Style.space(82), logical.width * root.fitScale)
        height: Math.max(Style.space(46), logical.height * root.fitScale)
        x: layoutX()
        y: layoutY()
        radius: Style.cornerRadius
        color: selected ? Style.selectedFillFor(root.foreground, Color.accent)
          : Style.controlFill(false, false, root.foreground, Color.accent)
        border.width: selected ? Style.normalBorderWidth * 2 : Style.normalBorderWidth
        border.color: selected ? Color.accent : Qt.darker(root.foreground, 1.8)

        Column {
          anchors.centerIn: parent
          width: parent.width - Style.space(8)
          spacing: Style.space(1)
          Text {
            text: displayCard.modelData.name
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }
          Text {
            text: displayCard.summary.split(" - ")[0]
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          drag.target: displayCard
          drag.minimumX: 0
          drag.maximumX: stage.width - displayCard.width
          drag.minimumY: 0
          drag.maximumY: stage.height - displayCard.height
          onPressed: {
            displayCard.pressX = displayCard.x
            displayCard.pressY = displayCard.y
          }
          onReleased: {
            if (Math.abs(displayCard.x - displayCard.pressX) < 2
                && Math.abs(displayCard.y - displayCard.pressY) < 2) {
              displayCard.restoreLayoutBinding()
              return
            }
            var requestedX = (displayCard.x - (stage.width - root.bounds.width * root.fitScale) / 2)
              / root.fitScale + root.bounds.minX
            var requestedY = (displayCard.y - (stage.height - root.bounds.height * root.fitScale) / 2)
              / root.fitScale + root.bounds.minY
            var finalPosition = root.arrangePosition(displayCard.modelData.name, requestedX, requestedY)
            if (finalPosition.x === Number(displayCard.modelData.x || 0)
                && finalPosition.y === Number(displayCard.modelData.y || 0)) {
              displayCard.restoreLayoutBinding()
              return
            }
            root.positionRequested(displayCard.modelData.name, finalPosition.x, finalPosition.y)
          }
        }

        Connections {
          target: root
          function onDisplaysChanged() { displayCard.restoreLayoutBinding() }
        }
      }
    }
  }
}
