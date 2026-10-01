import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Date/time label for the bar, and the host for the calendar popup.
//
// Left click reveals the calendar — asking "what is the date?" is what a
// click on a clock means — right click walks the common label formats, and
// middle click opens the timezone picker.
BarWidget {
  id: root
  moduleName: "omarchy.clock"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  // The clock fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line — the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root.vertical ? buttonVert : button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property string modeFilePath: (Quickshell.env("ANCHOR_SHELL_CONFIG_DIR")
    || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/anchor-shell"))
    + "/mode"
  property string storedMode: ""

  FileView {
    id: modeFileWatcher
    path: root.modeFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.storedMode = text().trim()
    onFileChanged: reload()
    onLoadFailed: root.storedMode = ""
  }

  readonly property string shellRootPath: root.bar && root.bar.shell ? root.bar.shell.shellPath : (Quickshell.env("QUICKSHELL_ROOT") || "")
  readonly property bool isDevMode: storedMode === "dev" || (shellRootPath !== "" && !shellRootPath.startsWith("/nix/store"))

  function exitDevModeAndDeploy() {
    var cmd = "xdg-terminal-exec --app-id=org.omarchy.terminal --title='Anchor Shell Deploy' /home/tetsuya/nixos-config/modules/anchor-shell/bin/anchor-shell-deploy"
    Util.execDetached(cmd)
  }

  function reloadDevMode() {
    Util.execDetached("quickshell-mode dev")
  }

  function exitDevModeOnly() {
    Util.execDetached("quickshell-mode nix")
  }

  implicitWidth: root.vertical
    ? (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal)
    : (button.implicitWidth + (root.isDevMode ? devButton.implicitWidth + contentRow.spacing : 0))
  implicitHeight: root.vertical
    ? (buttonVert.implicitHeight + (root.isDevMode ? devButtonVert.implicitHeight + contentCol.spacing : 0))
    : (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal)

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

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

  IpcHandler {
    target: "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function toggleDevMenu(): void { devMenu.open = !devMenu.open }
  }

  // Horizontal layout
  Row {
    id: contentRow
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    BarIconButton {
      id: devButton
      visible: root.isDevMode
      bar: root.bar
      text: "󰅩"
      slotSize: Style.bar.iconSlot
      tooltipText: "Developer Mode (Click for actions)"
      active: true
      useActiveColor: true
      activeColor: "#eab308"
      onPressed: function(b) {
        devMenu.open = !devMenu.open
      }
    }

    WidgetButton {
      id: button
      bar: root.bar
      text: root.displayText
      labelVisible: true
      hasVisualContent: text !== ""
      horizontalMargin: 8.75
      verticalPadding: 8.75

      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleFormat()
        else if (b === Qt.MiddleButton) root.cycleFormat()
        else root.togglePanel()
      }
    }
  }

  // Vertical layout
  Column {
    id: contentCol
    visible: root.vertical
    anchors.centerIn: parent
    spacing: Style.space(2)

    BarIconButton {
      id: devButtonVert
      visible: root.isDevMode
      bar: root.bar
      text: "󰅩"
      slotSize: Style.bar.iconSlot
      tooltipText: "Developer Mode (Click for actions)"
      active: true
      useActiveColor: true
      activeColor: "#eab308"
      onPressed: function(b) {
        devMenu.open = !devMenu.open
      }
    }

    WidgetButton {
      id: buttonVert
      bar: root.bar
      text: ""
      labelVisible: false
      hasVisualContent: root.verticalLines.length > 0
      fixedHeight: root.verticalLines.length * Style.bar.iconSlot
      horizontalMargin: 8.75
      verticalPadding: 8.75

      onPressed: function(b) {
        if (b === Qt.RightButton) root.cycleFormat()
        else if (b === Qt.MiddleButton) root.cycleFormat()
        else root.togglePanel()
      }

      Column {
        anchors.fill: parent

        Repeater {
          model: root.verticalLines

          OpticalGlyph {
            required property string modelData
            width: buttonVert.width
            height: Style.bar.iconSlot
            text: modelData
            fontFamily: buttonVert.fontFamily
            fontSize: modelData.length > 3
              ? buttonVert.fontSize * 0.9
              : buttonVert.fontSize
            color: buttonVert.foreground
          }
        }
      }
    }
  }

  PopupCard {
    id: devMenu
    anchorItem: root.vertical ? devButtonVert : devButton
    bar: root.bar
    owner: root
    open: false
    contentWidth: devMenu.fittedContentWidth(Style.space(270))
    contentHeight: devMenu.fittedContentHeight(devMenuCol.implicitHeight)

    Column {
      id: devMenuCol
      width: parent.width
      spacing: Style.space(6)

      Row {
        spacing: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right

        Text {
          text: "󰅩"
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          color: "#eab308"
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            text: "Developer Mode"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            color: Color.popups.text
          }

          Text {
            text: "Running from workspace"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Util.alpha(Color.popups.text, 0.6)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(Color.popups.text, 0.12)
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰏔"
        text: "Exit Dev Mode & Deploy"
        tooltipText: "Stage changes, run nixos-rebuild switch, and return to store mode"
        onClicked: {
          devMenu.open = false
          root.exitDevModeAndDeploy()
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰑐"
        text: "Reload Shell (Dev)"
        tooltipText: "Restart Quickshell reloading current workspace files"
        onClicked: {
          devMenu.open = false
          root.reloadDevMode()
        }
      }

      Button {
        width: parent.width
        leftAlign: true
        iconText: "󰈆"
        text: "Exit Dev Mode (No Deploy)"
        tooltipText: "Return to production store mode without rebuilding"
        onClicked: {
          devMenu.open = false
          root.exitDevModeOnly()
        }
      }
    }
  }
}
