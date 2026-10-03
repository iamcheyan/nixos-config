import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel

BarWidget {
  id: root
  moduleName: "omarchy.tray"

  property bool expanded: false
  property bool groupHovered: false
  property bool hoverExitPending: false
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  onAllItemsChanged: console.log("[TRAYDBG] all:", allItems.length, "pinned:", pinnedItems.length, "drawer:", drawerItems.length, "raw:", SystemTray.items.values.length, JSON.stringify(SystemTray.items.values.map(function(i){return i.id + "/" + i.status})))
  // Tray and indicator icons share the same standard bar slot size.
  readonly property int trayItemExtent: Style.bar.iconSlot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  // Inactive indicators and the tray drawer open and close together, at once:
  // no animation and no staggering between the two groups.
  readonly property bool indicatorsRevealed: expanded
  readonly property real revealProgress: expanded ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  // Short grace period so moving the pointer across the gap between two icons
  // does not collapse the group; the collapse itself is instant.
  Timer {
    id: hoverDebounceTimer
    interval: 150
    onTriggered: {
      if (root.hoverExitPending && !root.managePopupOpen && !root.trayMenuOpen) {
        root.groupHovered = false
        root.hoverExitPending = false
        root.expanded = false
      }
    }
  }

  function updateHoveredState(hovered) {
    if (hovered) {
      root.groupHovered = true
      root.hoverExitPending = false
      hoverDebounceTimer.stop()
      root.expanded = true
    } else {
      root.hoverExitPending = true
      hoverDebounceTimer.restart()
    }
  }

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    var source = String(icon || "")
    // Telegram switches to a tiny attention badge when it has notifications;
    // use the installed app icon so the tray keeps a recognizable Telegram mark.
    if (source === "image://icon/org.telegram.desktop-attention-symbolic")
      return "image://icon/org.telegram.desktop"
    return source
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  // Detect input method items (such as Fcitx / IBus / Rime)
  function isInputMethodItem(item) {
    if (!item) return false
    var id = String(item.id || "").toLowerCase()
    var icon = String(item.icon || "").toLowerCase()
    return id === "fcitx" || id.indexOf("fcitx") !== -1 || icon.indexOf("fcitx") !== -1 || icon.indexOf("input-keyboard") !== -1
  }

  // Detect whether the input method is currently in Chinese or English mode
  function inputMethodStatus(item) {
    if (!item) return "zh"
    var icon = String(item.icon || "").toLowerCase()
    var title = String(item.title || item.tooltipTitle || "").toLowerCase()
    if (icon.indexOf("image://icon/") === 0) icon = icon.substring(13)
    if (icon.indexOf("keyboard") !== -1 || icon.indexOf("latin") !== -1) {
      return "en"
    }
    if (icon.indexOf("rime") !== -1 || icon.indexOf("pinyin") !== -1 || icon.indexOf("chinese") !== -1 || icon.indexOf("wubi") !== -1 || icon.indexOf("_im") !== -1 || title.indexOf("rime") !== -1) {
      return "zh"
    }
    return "zh"
  }

  function needsTrayFallback(item) {
    if (!item) return false
    if (isInputMethodItem(item)) return true
    var icon = String(item && item.icon || "").toLowerCase()
    return icon === "image://icon/input-keyboard-symbolic"
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  function persistTrayState(pinned, hidden) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "omarchy.tray"
    root.bar.shell.updateEntryInline(id, { id: id, pinned: pinned, hidden: hidden })
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  // Active indicators are hosted inside this widget, so keep it loaded even
  // when no application currently contributes a tray item.
  visible: true
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property var indicatorsModule: indicatorStrip.item
      readonly property int indicatorWidth: indicatorStrip.item ? indicatorStrip.item.implicitWidth : 0
      readonly property int pinnedWidth: pinnedRow.implicitWidth
      readonly property int drawerRevealedWidth: Math.round(root.revealExtent)

      implicitWidth: indicatorWidth + drawerRevealedWidth + pinnedWidth
      implicitHeight: root.barSize

      HoverHandler {
        id: combinedHoverHandler
        onHoveredChanged: root.updateHoveredState(hovered || (indicatorStrip.item && indicatorStrip.item.isHovered))
      }

      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.managePopupOpen = !root.managePopupOpen
      }

      Row {
        id: mainRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        // The bar's right section is right-anchored, so anything that grows
        // pushes everything on its left outward. Keep the tray drawer on the
        // outermost side: [drawer][inactive indicators][active indicators][pinned].
        // Revealing either group then never moves the indicators already shown.
        Item {
          id: trayClip
          anchors.verticalCenter: parent.verticalCenter
          width: horizontalTrayRoot.drawerRevealedWidth
          height: root.barSize
          visible: horizontalTrayRoot.drawerRevealedWidth > 0
          clip: true

          Row {
            id: trayIcons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }

        Loader {
          id: indicatorStrip
          anchors.verticalCenter: parent.verticalCenter
          source: Qt.resolvedUrl("Indicators.qml")
          onLoaded: {
            if ("bar" in item) item.bar = Qt.binding(function() { return root.bar })
            if ("settings" in item) item.settings = ({})
            if ("externalReveal" in item) item.externalReveal = Qt.binding(function() { return root.indicatorsRevealed })
          }
          Connections {
            target: indicatorStrip.item
            ignoreUnknownSignals: true
            function onIsHoveredChanged() {
              root.updateHoveredState(combinedHoverHandler.hovered || indicatorStrip.item.isHovered)
            }
          }
        }

        Row {
          id: pinnedRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.trayItemGap
          leftPadding: root.pinnedItems.length > 0 && horizontalTrayRoot.drawerRevealedWidth > 0 ? root.trayJoinGap : 0
          Repeater {
            model: root.pinnedItems
            TrayItem {}
          }
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property var indicatorsModule: indicatorStrip.item
      readonly property int indicatorHeight: indicatorStrip.item ? indicatorStrip.item.implicitHeight : 0
      readonly property int pinnedHeight: pinnedCol.implicitHeight
      readonly property int drawerRevealedHeight: Math.round(root.revealExtent)

      implicitWidth: root.barSize
      implicitHeight: indicatorHeight + drawerRevealedHeight + pinnedHeight

      HoverHandler {
        id: combinedHoverHandler
        onHoveredChanged: root.updateHoveredState(hovered || (indicatorStrip.item && indicatorStrip.item.isHovered))
      }

      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.managePopupOpen = !root.managePopupOpen
      }

      Column {
        id: mainCol
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0

        Item {
          id: trayClip
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: verticalTrayRoot.drawerRevealedHeight
          visible: verticalTrayRoot.drawerRevealedHeight > 0
          clip: true

          Column {
            id: trayIcons
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }

        Loader {
          id: indicatorStrip
          anchors.horizontalCenter: parent.horizontalCenter
          source: Qt.resolvedUrl("Indicators.qml")
          onLoaded: {
            if ("bar" in item) item.bar = Qt.binding(function() { return root.bar })
            if ("settings" in item) item.settings = ({})
            if ("externalReveal" in item) item.externalReveal = Qt.binding(function() { return root.indicatorsRevealed })
          }
          Connections {
            target: indicatorStrip.item
            ignoreUnknownSignals: true
            function onIsHoveredChanged() {
              root.updateHoveredState(combinedHoverHandler.hovered || indicatorStrip.item.isHovered)
            }
          }
        }

        Column {
          id: pinnedCol
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: root.trayItemGap
          topPadding: root.pinnedItems.length > 0 && verticalTrayRoot.drawerRevealedHeight > 0 ? root.trayJoinGap : 0
          Repeater {
            model: root.pinnedItems
            TrayItem {}
          }
        }
      }
    }
  }

  PopupCard {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(300))
    contentHeight: managePopup.fittedContentHeight(manageColumn.implicitHeight)

    Column {
      id: manageColumn
      anchors.fill: parent
      spacing: Style.space(8)

      Text {
        text: "Tray icons"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        text: "Pinned icons stay visible. Hidden icons never show."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Text {
        visible: root.allItems.length === 0
        text: "No tray items reporting."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: true
      }

      Repeater {
        model: root.allItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          required property int index
          width: manageColumn.width
          implicitHeight: 28

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: 16
            height: 16
            item: rowRoot.modelData
            icon: rowRoot.modelData.icon
            fallbackText: rowRoot.displayName
            forceFallback: root.needsTrayFallback(rowRoot.modelData)
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(10)
            anchors.right: rowHideBtn.left
            anchors.rightMargin: Style.space(8)
            text: rowRoot.displayName
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Button {
            id: rowPinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            iconText: "\uf08d"
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.togglePin(rowRoot.itemId)
          }

          Button {
            id: rowHideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: rowPinBtn.left
            anchors.rightMargin: Style.space(6)
            iconText: "\uf06e"
            text: rowRoot.isHidden ? "Show" : "Hide"
            foreground: root.foreground
            horizontalPadding: 8
            verticalPadding: 3
            iconSize: Style.font.bodySmall
            fontSize: Style.font.bodySmall
            onClicked: root.toggleHide(rowRoot.itemId)
          }
        }
      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  PopupCard {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (visible stays true for that whole time --
    // see PopupCard's own visible: open || card.opacity > 0), so resetting on
    // "open" would swap a live submenu for the root menu mid-fade: a visible
    // flash, and a resize/reposition if the two have different geometry. Wait
    // for the fade to actually finish. Switching to a different tray item
    // still resets immediately, from openTrayMenu() itself.
    onVisibleChanged: if (!visible) root.resetTrayMenu()
    padding: Style.space(8)
    borderColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(232))
    contentHeight: trayMenuPopup.fittedContentHeight(menuHeaderHeight + trayMenuColumn.implicitHeight, Style.space(420))

    // Column skips invisible children but keeps reporting their height, so
    // read the header's extent through its own visibility.
    readonly property int menuHeaderHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

    Column {
      id: trayMenuLayout
      anchors.fill: parent
      spacing: 0

      // Header for a drilled-into submenu: names where we are and walks back
      // out. Pinned above the Flickable rather than scrolling with the rows,
      // so the way back stays reachable in a submenu taller than the card.
      // Only present below the root level, so the root menu is unchanged.
      Column {
        id: menuHeader
        visible: root.submenuDepth > 0
        width: trayMenuLayout.width
        spacing: 0

        Item {
          id: menuBackRow
          width: menuHeader.width
          implicitHeight: Style.space(30)

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: backMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: "\u2039"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(28)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            text: root.currentTitle
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.menuLevelSettling) return
              // Reset before the model swap so the parent level shows from
              // the top (same ordering as the row delegate below).
              trayMenuFlick.contentY = 0
              root.leaveSubmenu()
            }
          }
        }

        Item {
          width: menuHeader.width
          implicitHeight: Style.space(11)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: Color.popups.border
            opacity: 0.45
          }
        }
      }

      Flickable {
        id: trayMenuFlick
        width: trayMenuLayout.width
        height: trayMenuLayout.height - trayMenuPopup.menuHeaderHeight
        contentWidth: width
        contentHeight: trayMenuColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: trayMenuColumn
          width: trayMenuFlick.width
          spacing: 0

          Repeater {
            model: root.currentChildren

            delegate: Item {
              id: menuRow
              required property var modelData
              required property int index

              readonly property string rowText: String(modelData.text || "")
              readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
              // Both only ever describe the root menu; inside a submenu the first
              // rows are real entries and must not be swallowed.
              readonly property bool atRoot: root.submenuDepth === 0
              readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
              readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
              readonly property bool hiddenRow: rootTitleEntry || leadingSeparator

              visible: !hiddenRow
              width: trayMenuColumn.width
              implicitHeight: hiddenRow ? 0 : (modelData.isSeparator ? Style.space(11) : Style.space(30))
              opacity: modelData.enabled ? 1.0 : 0.45

              Rectangle {
                visible: menuRow.modelData.isSeparator
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Color.popups.border
                opacity: 0.45
              }

              Rectangle {
                visible: !menuRow.modelData.isSeparator
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius)
                color: rowMouse.containsMouse && menuRow.modelData.enabled ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.buttonType !== QsMenuButtonType.None
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: menuRow.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Image {
                id: menuIcon
                visible: !menuRow.modelData.isSeparator && String(menuRow.modelData.icon || "") !== ""
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(24)
                width: Style.space(16)
                height: Style.space(16)
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels: IconImage uses the logical size,
                // which leaves PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: menuRow.modelData.icon
              }

              Text {
                textFormat: Text.PlainText
                visible: !menuRow.modelData.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: menuIcon.visible ? Style.space(46) : Style.space(28)
                anchors.right: submenuGlyph.left
                anchors.rightMargin: Style.space(8)
                text: menuRow.rowText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: submenuGlyph
                visible: !menuRow.modelData.isSeparator && menuRow.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                text: "\u203a"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !menuRow.modelData.isSeparator && menuRow.modelData.enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.menuLevelSettling) return
                  if (menuRow.modelData.hasChildren) {
                    // Reset scroll BEFORE swapping the model: the swap destroys
                    // this delegate synchronously and ids stop resolving after.
                    trayMenuFlick.contentY = 0
                    root.enterSubmenu(menuRow.modelData, menuRow.rowText)
                  } else {
                    menuRow.modelData.triggered()
                    root.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    property var item: null
    property string fallbackText: ""
    property bool forceFallback: false
    readonly property bool isInputMethod: root.isInputMethodItem(item)
    readonly property string imStatus: isInputMethod ? root.inputMethodStatus(item) : ""
    readonly property bool symbolic: root.iconIsSymbolic(icon)
    readonly property bool imageReady: trayIconImage.status === Image.Ready
    readonly property bool imageLoadFailed: trayIconImage.status === Image.Error || !hasIconSource
    readonly property bool hasIconSource: String(icon || "").trim() !== ""
    readonly property bool showFallback: forceFallback || imageLoadFailed || !hasIconSource || isInputMethod
    readonly property string fallbackGlyph: {
      if (isInputMethod) {
        return imStatus === "zh" ? "中" : "英"
      }
      var source = String(icon || "").toLowerCase()
      if (source.indexOf("input-keyboard") !== -1) return "英"
      var value = String(fallbackText || "").trim()
      return value ? value.charAt(0).toLocaleUpperCase() : "?"
    }

    Rectangle {
      anchors.fill: parent
      visible: trayIconRoot.showFallback && !trayIconRoot.isInputMethod
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
      border.width: Style.space(1)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.8)
    }

    Text {
      anchors.centerIn: parent
      visible: trayIconRoot.showFallback
      text: trayIconRoot.fallbackGlyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: trayIconRoot.isInputMethod
        ? Math.round(parent.height * 0.72)
        : Math.max(9, Math.round(parent.height * 0.68))
      font.bold: true
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }

    IconImage {
      id: trayIconImage
      anchors.fill: parent
      anchors.margins: Style.space(1)
      implicitSize: Style.bar.iconCanvas
      source: root.trayIconSource(trayIconRoot.icon)
      visible: !trayIconRoot.showFallback && trayIconRoot.hasIconSource && trayIconRoot.imageReady
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: !trayIconRoot.showFallback && trayIconRoot.hasIconSource && trayIconRoot.symbolic && trayIconRoot.imageReady
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData
    readonly property bool interactive: true
    readonly property bool pressable: true

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0
    width: implicitWidth
    height: implicitHeight

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    function triggerPress(button) {
      if (button === Qt.RightButton) {
        trayItemRoot.displayMenu({ x: width / 2, y: height / 2 })
      } else if (button === Qt.MiddleButton) {
        trayItemRoot.modelData.secondaryActivate()
      } else if (trayItemRoot.modelData.onlyMenu) {
        trayItemRoot.displayMenu({ x: width / 2, y: height / 2 })
      } else {
        trayItemRoot.modelData.activate()
      }
    }

    Component.onCompleted: if (root.bar && root.bar.registerClickTarget) root.bar.registerClickTarget(trayItemRoot)
    Component.onDestruction: if (root.bar && root.bar.unregisterClickTarget) root.bar.unregisterClickTarget(trayItemRoot)

    TrayIcon {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: Style.bar.iconCanvas
      item: trayItemRoot.modelData
      icon: trayItemRoot.modelData.icon
      fallbackText: trayItemRoot.modelData.title || trayItemRoot.modelData.tooltipTitle || trayItemRoot.modelData.id || "?"
      forceFallback: root.needsTrayFallback(trayItemRoot.modelData)
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
