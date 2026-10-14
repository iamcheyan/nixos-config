import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "DockModel.js" as DockModel

Item {
  id: dock
  required property var screen
  property var shell: null
  property var dockRoot: null

  readonly property var settings: dockRoot ? dockRoot.dockSettings : ({})
  readonly property int dockWidth: settings.dockWidth || 40
  readonly property int iconBox: settings.iconBox || 28
  readonly property int iconSize: settings.iconSize || 22
  readonly property int iconGap: settings.iconGap === 0 ? 0 : (settings.iconGap || 2)
  readonly property int pillPad: settings.pillPad || 6
  readonly property int pillRadius: settings.pillRadius || 16
  readonly property int itemRadius: settings.itemRadius === 0 ? 0 : (settings.itemRadius || 8)
  readonly property real previewScale: {
    var count = dock.hoveredApp ? dock.hoveredApp.windows.length : 0
    var baseHeight = 36 + 186 * count
    return count > 0 ? Math.min(1, Math.max(0.01, (surface.height - 16) / baseHeight)) : 1
  }
  readonly property int iconPixels: {
    var dpr = (screen && screen.devicePixelRatio) ? screen.devicePixelRatio : 1
    return Math.max(1, Math.round(iconSize * dpr))
  }

  property var apps: []
  property int appCount: 0
  property var hoveredItem: null
  property string hoveredAppId: ""
  property bool previewArmed: false
  property var contextItem: null
  property bool contextMenuOpen: false
  property bool settingsOpen: false
  property bool dragging: false
  property int dragFromIndex: -1
  property int dropIndex: -1
  property real dragPointerY: 0
  property var dragApp: null
  readonly property int dragThreshold: 8
  readonly property int stride: iconBox + iconGap

  readonly property var hoveredApp: {
    var id = dock.hoveredAppId
    var list = dock.apps
    if (!id) return null
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i]
    }
    return null
  }
  readonly property int previewWindowCount: dock.hoveredApp ? dock.hoveredApp.windows.length : 0

  // xdg-popup cannot be resized in place. A visible preview that shrinks
  // (3 windows → 1, or a different source aspect) keeps the old buffer and
  // stretches ScreencopyView into it. Tear the popup down and recreate it.
  function rearmPreview() {
    dock.previewArmed = false
    if (dock.hoveredAppId !== "" && dock.previewWindowCount > 0
        && !dock.contextMenuOpen && !dock.dragging) {
      previewArmTimer.restart()
    } else {
      previewArmTimer.stop()
    }
  }

  function scheduleRefresh() {
    if (!refreshTimer.running) refreshTimer.start()
  }

  function refreshApps() {
    if (dock.dragging) return
    if (!dockRoot) {
      dock.apps = []
      dock.appCount = 0
      return
    }
    var next = DockModel.buildApps({
      pinnedApps: dockRoot.pinnedApps,
      toplevels: ToplevelManager.toplevels.values || [],
      screen: dock.screen,
      activeToplevel: ToplevelManager.activeToplevel,
      nameFor: function(id) { return dockRoot.nameFor(id) },
      iconFor: function(id) { return dockRoot.iconFor(id) }
    })
    if (DockModel.listsMatch(dock.apps, next)) return
    dock.apps = next
    dock.appCount = next.length
    if (dock.hoveredAppId && !DockModel.containsApp(next, dock.hoveredAppId))
      dock.clearHover()
    if (dock.contextMenuOpen && dock.contextItem && dock.contextItem.app
        && !DockModel.containsApp(next, dock.contextItem.app.id)) {
      dock.contextMenuOpen = false
      dock.contextItem = null
    }
  }

  function setHoveredItem(item) {
    hoverCloseTimer.stop()
    if (dock.contextMenuOpen || dock.dragging) return
    dock.hoveredItem = item
    dock.hoveredAppId = item && item.app ? item.app.id : ""
  }

  function indexAtY(y) {
    if (dock.appCount <= 0 || dock.stride <= 0) return 0
    var i = Math.round((y - dock.iconBox / 2) / dock.stride)
    return Math.max(0, Math.min(dock.appCount - 1, i))
  }

  function beginDrag(index) {
    if (index < 0 || index >= dock.apps.length) return
    dock.dragging = true
    dock.dragFromIndex = index
    dock.dropIndex = index
    dock.dragApp = dock.apps[index]
    dock.contextMenuOpen = false
    dock.contextItem = null
    dock.clearHover()
  }

  function updateDrag(yInColumn) {
    if (!dock.dragging) return
    dock.dragPointerY = yInColumn
    dock.dropIndex = dock.indexAtY(yInColumn)
  }

  function cancelDrag() {
    dock.dragging = false
    dock.dragFromIndex = -1
    dock.dropIndex = -1
    dock.dragApp = null
  }

  function endDrag() {
    if (!dock.dragging) return
    var from = dock.dragFromIndex
    var to = dock.dropIndex
    var dragged = dock.dragApp
    dock.cancelDrag()
    if (from < 0 || to < 0 || from === to || !dragged || !dockRoot) return
    var next = DockModel.moveItem(dock.apps, from, to)
    var ids = []
    for (var i = 0; i < next.length; i++) ids.push(next[i].id)
    dockRoot.commitOrder(ids, dragged.id)
    dock.apps = next
    dock.appCount = next.length
    dock.scheduleRefresh()
  }

  function clearHover() {
    dock.hoveredItem = null
    dock.hoveredAppId = ""
    dock.previewArmed = false
    previewArmTimer.stop()
  }

  function handleItemClick(app, item) {
    if (!app) return
    if (app.windows.length === 0) {
      dockRoot.launchApp(app.id)
    } else if (app.windows.length === 1) {
      var w = app.windows[0]
      if (w.minimized) {
        w.minimized = false
        w.activate()
      } else if (w.activated) {
        w.minimized = true
      } else {
        w.activate()
      }
    } else {
      dock.contextMenuOpen = false
      if (dock.hoveredAppId === app.id) dock.clearHover()
      else dock.setHoveredItem(item)
    }
  }

  function calcPopupY(item, popupH) {
    if (!item) return 12
    var itemPos = item.mapToItem(null, 0, 0)
    var targetY = itemPos.y + (item.height / 2) - (popupH / 2)
    return Math.max(8, Math.min(surface.height - popupH - 8, targetY))
  }

  function calcContextMenuY(item, menuH) {
    if (!item) return 12
    var itemPos = item.mapToItem(null, 0, 0)
    var targetY = itemPos.y + (item.height / 2) - (menuH / 2)
    return Math.max(8, Math.min(surface.height - menuH - 8, targetY))
  }

  Timer {
    id: refreshTimer
    interval: 16
    repeat: false
    onTriggered: dock.refreshApps()
  }

  Timer {
    id: hoverCloseTimer
    interval: 250
    repeat: false
    onTriggered: {
      if (!dockHover.hovered && !previewHover.hovered && !dock.contextMenuOpen)
        dock.clearHover()
    }
  }

  Timer {
    id: previewArmTimer
    interval: 0
    repeat: false
    onTriggered: {
      dock.previewArmed = dock.hoveredAppId !== "" && dock.previewWindowCount > 0
        && !dock.contextMenuOpen && !dock.dragging
    }
  }

  Component.onCompleted: dock.scheduleRefresh()
  onDockRootChanged: dock.scheduleRefresh()
  onPreviewWindowCountChanged: dock.rearmPreview()

  Connections {
    target: dockRoot
    function onPinnedAppsChanged() { dock.scheduleRefresh() }
    function onCacheGenerationChanged() { dock.scheduleRefresh() }
  }
  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { dock.scheduleRefresh() }
  }
  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { dock.scheduleRefresh() }
  }

  PanelWindow {
    id: surface
    screen: dock.screen
    anchors { left: true; top: true; bottom: true }
    margins {
      top: (typeof shell !== "undefined" && shell.bar && !shell.bar.barHidden) ? shell.bar.barSize : 32
    }
    implicitWidth: dock.dockWidth
    color: "transparent"
    exclusionMode: ExclusionMode.Auto
    WlrLayershell.namespace: "anchor-omadock"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusiveZone: dock.dockWidth

    MouseArea {
      anchors.fill: parent
      z: -1
      onClicked: {
        dock.contextMenuOpen = false
        dock.clearHover()
      }
    }

    HoverHandler {
      id: dockHover
      onHoveredChanged: {
        if (hovered) hoverCloseTimer.stop()
        else if (!previewHover.hovered && !dock.contextMenuOpen) hoverCloseTimer.restart()
      }
    }

    Rectangle {
      id: dockPill
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: dock.dockWidth
      height: Math.min(surface.height - 24, Math.max(64, appColumn.implicitHeight + dock.pillPad * 2))
      radius: dock.pillRadius
      color: Qt.rgba(0.125, 0.125, 0.153, (settings.opacity || 86) / 100)
      border.width: 0

      Flickable {
        anchors.fill: parent
        anchors.topMargin: dock.pillPad
        anchors.bottomMargin: dock.pillPad
        contentWidth: width
        contentHeight: appColumn.implicitHeight
        clip: true
        interactive: contentHeight > height && !dock.dragging

        Column {
          id: appColumn
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: dock.iconGap

          Repeater {
            model: dock.appCount
            delegate: Item {
              id: appItem
              required property int index
              readonly property var app: dock.apps[index] || null
              width: dock.iconBox
              height: dock.iconBox
              visible: appItem.app !== null
              opacity: (dock.dragging && index === dock.dragFromIndex) ? 0.35 : 1
              property real pressX: 0
              property real pressY: 0
              property bool didDrag: false

              Rectangle {
                visible: !dock.dragging && appItem.app && appItem.app.isSeparatorBefore
                anchors.top: parent.top
                anchors.topMargin: -1
                anchors.horizontalCenter: parent.horizontalCenter
                width: 22
                height: 1
                color: "#44ffffff"
              }

              Rectangle {
                anchors.fill: parent
                radius: dock.itemRadius
                color: mouse.containsMouse ? "#22ffffff" : "transparent"
              }

              Rectangle {
                visible: appItem.app && appItem.app.isRunning
                anchors.left: parent.left
                anchors.leftMargin: -2
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: appItem.app && appItem.app.isActive ? 10 : 4
                radius: 2
                color: appItem.app && appItem.app.isActive ? "#ffffff" : "#b0ffffff"
              }

              Image {
                id: appIconImage
                anchors.centerIn: parent
                width: dock.iconSize
                height: dock.iconSize
                source: appItem.app ? appItem.app.icon : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: false
                smooth: true
                visible: status === Image.Ready
                sourceSize.width: DockModel.iconIsRaster(source) ? dock.iconPixels : 0
                sourceSize.height: DockModel.iconIsRaster(source) ? dock.iconPixels : 0
              }

              Text {
                anchors.centerIn: parent
                text: appItem.app && appItem.app.name ? appItem.app.name.charAt(0).toUpperCase() : "A"
                color: "white"
                font.pixelSize: 11
                font.bold: true
                visible: appIconImage.status !== Image.Ready
              }

              Rectangle {
                visible: appItem.app && appItem.app.windows.length > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 12
                height: 12
                radius: 6
                color: "#dc334155"
                Text {
                  anchors.centerIn: parent
                  text: appItem.app ? appItem.app.windows.length : ""
                  color: "white"
                  font.pixelSize: 8
                  font.bold: true
                }
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true

                onEntered: dock.setHoveredItem(appItem)
                onExited: {
                  if (!dock.dragging && !previewHover.hovered && !dock.contextMenuOpen)
                    hoverCloseTimer.restart()
                }

                onPressed: function(mouseEvent) {
                  appItem.didDrag = false
                  appItem.pressX = mouseEvent.x
                  appItem.pressY = mouseEvent.y
                  if (mouseEvent.button === Qt.RightButton) {
                    dock.cancelDrag()
                    dock.clearHover()
                    dock.contextItem = appItem
                    dock.contextMenuOpen = true
                  }
                }

                onPositionChanged: function(mouseEvent) {
                  if (!(mouseEvent.buttons & Qt.LeftButton)) return
                  if (dock.contextMenuOpen) return
                  var dx = mouseEvent.x - appItem.pressX
                  var dy = mouseEvent.y - appItem.pressY
                  if (!dock.dragging) {
                    if (Math.abs(dx) < dock.dragThreshold && Math.abs(dy) < dock.dragThreshold)
                      return
                    appItem.didDrag = true
                    dock.beginDrag(appItem.index)
                  }
                  var pos = appItem.mapToItem(appColumn, mouseEvent.x, mouseEvent.y)
                  dock.updateDrag(pos.y)
                }

                onReleased: function(mouseEvent) {
                  if (mouseEvent.button === Qt.LeftButton && dock.dragging)
                    dock.endDrag()
                }

                onCanceled: dock.cancelDrag()

                onClicked: function(mouseEvent) {
                  if (appItem.didDrag || dock.dragging) return
                  if (mouseEvent.button === Qt.RightButton) {
                    dock.clearHover()
                    dock.contextItem = appItem
                    dock.contextMenuOpen = true
                  } else {
                    dock.contextMenuOpen = false
                    dock.handleItemClick(appItem.app, appItem)
                  }
                }
              }
            }
          }
        }

        Item {
          id: dragOverlay
          anchors.horizontalCenter: parent.horizontalCenter
          width: dock.iconBox
          height: appColumn.implicitHeight
          visible: dock.dragging
          z: 10

          Rectangle {
            visible: dock.dropIndex >= 0 && dock.dropIndex !== dock.dragFromIndex
            y: dock.dropIndex * dock.stride
            width: dock.iconBox
            height: dock.iconBox
            radius: dock.itemRadius
            color: "#28ffffff"
            border.color: "#66ffffff"
            border.width: 1
          }

          Item {
            width: dock.iconBox
            height: dock.iconBox
            y: Math.max(0, Math.min(dragOverlay.height - height, dock.dragPointerY - dock.iconBox / 2))
            Image {
              anchors.centerIn: parent
              width: dock.iconSize
              height: dock.iconSize
              source: dock.dragApp ? dock.dragApp.icon : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: false
              cache: false
              smooth: true
              sourceSize.width: DockModel.iconIsRaster(source) ? dock.iconPixels : 0
              sourceSize.height: DockModel.iconIsRaster(source) ? dock.iconPixels : 0
            }
          }
        }
      }
    }

    PopupWindow {
      id: previews
      visible: dock.previewArmed && dock.hoveredApp !== null && dock.hoveredApp.windows.length > 0
        && !dock.contextMenuOpen && !dock.dragging
      color: "transparent"
      implicitWidth: 268 * dock.previewScale
      implicitHeight: (previewColumn.implicitHeight + 16) * dock.previewScale
      anchor {
        window: surface
        rect.x: dock.dockWidth
        rect.y: dock.calcPopupY(dock.hoveredItem, previews.implicitHeight)
        rect.width: 1
        rect.height: 1
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Slide
      }

      Item {
        id: previewContent
        width: 268
        height: previewColumn.implicitHeight + 16
        scale: dock.previewScale
        transformOrigin: Item.TopLeft

        Rectangle {
          id: previewCard
          anchors.fill: parent
          radius: 10
          color: "#f21c1c24"
          border.color: "#3dffffff"
          border.width: 1

          HoverHandler {
            id: previewHover
            onHoveredChanged: {
              if (hovered) hoverCloseTimer.stop()
              else if (!dock.contextMenuOpen) hoverCloseTimer.restart()
            }
          }

          Column {
            id: previewColumn
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 6

            Row {
              spacing: 8
              width: parent.width
              Image {
                width: 16; height: 16
                anchors.verticalCenter: parent.verticalCenter
                source: dock.hoveredApp ? dock.hoveredApp.icon : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: false
                cache: false
                sourceSize.width: DockModel.iconIsRaster(source) ? 32 : 0
                sourceSize.height: DockModel.iconIsRaster(source) ? 32 : 0
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: dock.hoveredApp ? dock.hoveredApp.name : ""
                color: "#e2e8f0"
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (dock.hoveredApp && dock.hoveredApp.windows.length > 0)
                  ? "(" + dock.hoveredApp.windows.length + ")" : ""
                color: "#94a3b8"
                font.pixelSize: 11
                visible: text !== ""
              }
            }

            Repeater {
              model: dock.hoveredApp ? dock.hoveredApp.windows : []
              delegate: Rectangle {
                id: windowItem
                required property var modelData
                required property int index
                width: previewColumn.width
                height: 180
                radius: 10
                color: windowMouse.containsMouse ? "#33ffffff" : (windowItem.modelData.activated ? "#24ffffff" : "#14ffffff")
                border.color: windowItem.modelData.activated ? "#80ffffff" : (windowMouse.containsMouse ? "#55ffffff" : "#26ffffff")
                border.width: 1
                clip: true

                Column {
                  anchors.fill: parent
                  anchors.margins: 6
                  spacing: 6

                  Row {
                    width: parent.width
                    height: 20
                    spacing: 6

                    Image {
                      width: 16; height: 16
                      anchors.verticalCenter: parent.verticalCenter
                      source: dock.hoveredApp ? dock.hoveredApp.icon : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: false
                      cache: false
                      sourceSize.width: DockModel.iconIsRaster(source) ? 32 : 0
                      sourceSize.height: DockModel.iconIsRaster(source) ? 32 : 0
                    }

                    Text {
                      width: parent.width - 56
                      anchors.verticalCenter: parent.verticalCenter
                      text: windowItem.modelData.title || windowItem.modelData.appId || "Window"
                      color: "white"
                      font.pixelSize: 11
                      font.bold: windowItem.modelData.activated
                      elide: Text.ElideRight
                    }

                    Rectangle {
                      width: 18; height: 18
                      radius: 9
                      color: closeMouse.containsMouse ? "#e11d48" : "transparent"
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: closeMouse.containsMouse ? "white" : "#94a3b8"
                        font.pixelSize: 9
                        font.bold: true
                      }
                      MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: windowItem.modelData.close()
                      }
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: 142
                    radius: 6
                    color: "#0a0a0f"
                    clip: true

                    Loader {
                      id: thumbLoader
                      anchors.fill: parent
                      property var captureWin: windowItem.modelData
                      active: previews.visible && captureWin != null
                      sourceComponent: Component {
                        ScreencopyView {
                          anchors.centerIn: parent
                          constraintSize: Qt.size(thumbLoader.width, thumbLoader.height)
                          captureSource: thumbLoader.captureWin
                          live: true
                          visible: hasContent
                        }
                      }
                      onCaptureWinChanged: {
                        if (!previews.visible) return
                        active = false
                        Qt.callLater(function() {
                          thumbLoader.active = previews.visible && thumbLoader.captureWin != null
                        })
                      }
                    }

                    Item {
                      anchors.fill: parent
                      visible: !thumbLoader.item || !thumbLoader.item.hasContent
                      Image {
                        anchors.centerIn: parent
                        width: 36; height: 36
                        source: dock.hoveredApp ? dock.hoveredApp.icon : ""
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.5
                      }
                    }

                    Rectangle {
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      anchors.margins: 4
                      visible: windowItem.modelData.activated || windowItem.modelData.minimized
                      height: 16
                      width: badgeText.implicitWidth + 8
                      radius: 4
                      color: windowItem.modelData.activated ? "#2563eb" : "#475569"
                      Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: windowItem.modelData.activated ? "Active" : "Minimized"
                        color: "white"
                        font.pixelSize: 9
                      }
                    }
                  }
                }

                MouseArea {
                  id: windowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  anchors.topMargin: 26
                  onClicked: {
                    if (windowItem.modelData.minimized) windowItem.modelData.minimized = false
                    windowItem.modelData.activate()
                    dock.clearHover()
                  }
                }
              }
            }
        }
      }
      }
    }

    PopupWindow {
      id: contextMenu
      visible: dock.contextMenuOpen && dock.contextItem !== null
      color: "transparent"
      implicitWidth: 196
      implicitHeight: contextColumn.implicitHeight + 16
      anchor {
        window: surface
        rect.x: dock.dockWidth
        rect.y: dock.calcContextMenuY(dock.contextItem, contextMenu.implicitHeight)
        rect.width: 1
        rect.height: 1
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Slide
      }

      Rectangle {
        id: contextCard
        anchors.fill: parent
        radius: 10
        color: "#f21c1c24"
        border.color: "#3dffffff"
        border.width: 1

        Column {
          id: contextColumn
          anchors.fill: parent
          anchors.margins: 8
          spacing: 4

          Row {
            spacing: 8
            width: parent.width
            Image {
              width: 16; height: 16
              anchors.verticalCenter: parent.verticalCenter
              source: dock.contextItem && dock.contextItem.app ? dock.contextItem.app.icon : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: false
              cache: false
              sourceSize.width: DockModel.iconIsRaster(source) ? 32 : 0
              sourceSize.height: DockModel.iconIsRaster(source) ? 32 : 0
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: dock.contextItem && dock.contextItem.app ? dock.contextItem.app.name : ""
              color: "white"
              font.pixelSize: 12
              font.bold: true
              elide: Text.ElideRight
            }
          }

          Rectangle {
            width: parent.width; height: 1
            color: "#28ffffff"
          }

          Rectangle {
            width: parent.width; height: 26; radius: 6
            color: settingsMouse.containsMouse ? "#33ffffff" : "transparent"
            Row {
              anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
              Text { anchors.verticalCenter: parent.verticalCenter; text: "⚙"; color: "#e2e8f0"; font.pixelSize: 12 }
              Text { anchors.verticalCenter: parent.verticalCenter; text: "Dock Settings"; color: "#e2e8f0"; font.pixelSize: 11 }
            }
            MouseArea {
              id: settingsMouse; anchors.fill: parent; hoverEnabled: true
              onClicked: {
                dock.contextMenuOpen = false
                dock.settingsOpen = true
              }
            }
          }

          Rectangle {
            width: parent.width; height: 26; radius: 6
            color: newWinMouse.containsMouse ? "#33ffffff" : "transparent"
            Row {
              anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
              Text { anchors.verticalCenter: parent.verticalCenter; text: "➕"; font.pixelSize: 11 }
              Text { anchors.verticalCenter: parent.verticalCenter; text: "New Window"; color: "#e2e8f0"; font.pixelSize: 11 }
            }
            MouseArea {
              id: newWinMouse; anchors.fill: parent; hoverEnabled: true
              onClicked: {
                if (dock.contextItem && dock.contextItem.app && dock.dockRoot)
                  dock.dockRoot.launchApp(dock.contextItem.app.id)
                dock.contextMenuOpen = false
              }
            }
          }

          Rectangle {
            id: pinActionRow
            width: parent.width; height: 26; radius: 6
            color: pinMouse.containsMouse ? "#33ffffff" : "transparent"
            readonly property bool isPinned: dock.contextItem && dock.contextItem.app && dock.dockRoot
              && dock.dockRoot.isPinned(dock.contextItem.app.id)
            Row {
              anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
              Text { anchors.verticalCenter: parent.verticalCenter; text: pinActionRow.isPinned ? "⭐" : "📌"; font.pixelSize: 11 }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pinActionRow.isPinned ? "Remove from Dock" : "Pin to Dock"
                color: "#e2e8f0"
                font.pixelSize: 11
              }
            }
            MouseArea {
              id: pinMouse; anchors.fill: parent; hoverEnabled: true
              onClicked: {
                if (dock.contextItem && dock.contextItem.app && dock.dockRoot) {
                  var id = dock.contextItem.app.id
                  if (dock.dockRoot.isPinned(id)) dock.dockRoot.unpinApp(id)
                  else dock.dockRoot.pinApp(id)
                }
                dock.contextMenuOpen = false
              }
            }
          }

          Rectangle {
            visible: dock.contextItem && dock.contextItem.app && dock.contextItem.app.windows.length > 0
            width: parent.width; height: 26; radius: 6
            color: closeAllMouse.containsMouse ? "#44e11d48" : "transparent"
            Row {
              anchors.fill: parent; anchors.leftMargin: 8; spacing: 8
              Text { anchors.verticalCenter: parent.verticalCenter; text: "✕"; font.pixelSize: 11; color: "#f87171" }
              Text { anchors.verticalCenter: parent.verticalCenter; text: "Close All Windows"; color: "#f87171"; font.pixelSize: 11 }
            }
            MouseArea {
              id: closeAllMouse; anchors.fill: parent; hoverEnabled: true
              onClicked: {
                if (dock.contextItem && dock.contextItem.app) {
                  var wins = dock.contextItem.app.windows
                  for (var i = 0; i < wins.length; i++) wins[i].close()
                }
                dock.contextMenuOpen = false
              }
            }
          }
        }
      }
    }

    PopupWindow {
      id: settingsPanel
      visible: dock.settingsOpen
      color: "transparent"
      implicitWidth: 340
      implicitHeight: Math.min(surface.height - 24, settingsColumn.implicitHeight + 28)
      anchor {
        window: surface
        rect.x: dock.dockWidth
        rect.y: Math.max(12, Math.min(surface.height - settingsPanel.implicitHeight - 12,
          dock.contextItem ? dock.calcContextMenuY(dock.contextItem, Math.min(280, surface.height - 24)) : surface.height / 2 - settingsPanel.implicitHeight / 2))
        rect.width: 1
        rect.height: 1
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        adjustment: PopupAdjustment.Slide
      }

      Rectangle {
        anchors.fill: parent
        radius: 14
        color: "#f21c1c24"
        border.color: "#55ffffff"
        border.width: 1

        Flickable {
          anchors.fill: parent
          anchors.margins: 14
          contentWidth: width
          contentHeight: settingsColumn.implicitHeight
          clip: true
          interactive: contentHeight > height

          Column {
            id: settingsColumn
            width: parent.width
            spacing: 10

            Row {
              width: parent.width
              spacing: 8
              Column {
                width: parent.width - 70
                Text { text: "Dock Appearance & Layout"; color: "white"; font.pixelSize: 15; font.bold: true }
                Text { text: "Changes are saved automatically"; color: "#94a3b8"; font.pixelSize: 10 }
              }
              Rectangle {
                width: 28; height: 28; radius: 8
                color: closeSettingsMouse.containsMouse ? "#33ffffff" : "transparent"
                Text { anchors.centerIn: parent; text: "✕"; color: "#cbd5e1"; font.pixelSize: 12 }
                MouseArea { id: closeSettingsMouse; anchors.fill: parent; hoverEnabled: true; onClicked: dock.settingsOpen = false }
              }
            }

            Rectangle { width: parent.width; height: 1; color: "#28ffffff" }

            Repeater {
              model: [
                { key: "iconSize", label: "Icon Size", min: 14, max: 36, suffix: " px" },
                { key: "iconBox", label: "Icon Slot Size", min: 24, max: 52, suffix: " px" },
                { key: "iconGap", label: "Icon Spacing", min: 0, max: 18, suffix: " px" },
                { key: "dockWidth", label: "Dock Width", min: 36, max: 76, suffix: " px" },
                { key: "pillPad", label: "Vertical Padding", min: 2, max: 20, suffix: " px" },
                { key: "pillRadius", label: "Dock Corner Radius", min: 8, max: 32, suffix: " px" },
                { key: "itemRadius", label: "Hover Highlight Radius", min: 0, max: 20, suffix: " px" },
                { key: "opacity", label: "Dock & Top Bar Opacity", min: 20, max: 100, suffix: "%" }
              ]
              delegate: Column {
                id: settingRow
                required property var modelData
                width: settingsColumn.width
                spacing: 4
                property int currentValue: dock.settings[modelData.key] === undefined ? modelData.min : dock.settings[modelData.key]

                Row {
                  width: parent.width
                  Text { width: parent.width - 48; text: settingRow.modelData.label; color: "#dbe4ef"; font.pixelSize: 11 }
                  Text { width: 48; horizontalAlignment: Text.AlignRight; text: settingRow.currentValue + settingRow.modelData.suffix; color: "#94a3b8"; font.pixelSize: 10 }
                }
                Rectangle {
                  id: sliderTrack
                  width: parent.width
                  height: 16
                  color: "transparent"
                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 0; width: parent.width; height: 4; radius: 2; color: "#334155"
                    Rectangle {
                      width: sliderTrack.width * (settingRow.currentValue - settingRow.modelData.min) / (settingRow.modelData.max - settingRow.modelData.min)
                      height: parent.height; radius: 2; color: "#60a5fa"
                    }
                  }
                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, Math.min(sliderTrack.width - width,
                      sliderTrack.width * (settingRow.currentValue - settingRow.modelData.min) / (settingRow.modelData.max - settingRow.modelData.min) - width / 2))
                    width: 12; height: 12; radius: 6; color: "#e2e8f0"
                  }
                  MouseArea {
                    anchors.fill: parent
                    function updateValue(x) {
                      var ratio = Math.max(0, Math.min(1, x / width))
                      dock.dockRoot.setDockSetting(settingRow.modelData.key,
                        settingRow.modelData.min + ratio * (settingRow.modelData.max - settingRow.modelData.min))
                    }
                    onPressed: function(mouse) { updateValue(mouse.x) }
                    onPositionChanged: function(mouse) { if (pressed) updateValue(mouse.x) }
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: 8
              Rectangle {
                width: 108; height: 28; radius: 7
                color: resetMouse.containsMouse ? "#334155" : "#263241"
                Text { anchors.centerIn: parent; text: "Reset to Defaults"; color: "#cbd5e1"; font.pixelSize: 10 }
                MouseArea { id: resetMouse; anchors.fill: parent; hoverEnabled: true; onClicked: dock.dockRoot.resetDockSettings() }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Linked opacity · saved in dock.json and shell.json"
                color: "#64748b"
                font.pixelSize: 9
              }
            }
          }
        }
      }
    }
  }
}
