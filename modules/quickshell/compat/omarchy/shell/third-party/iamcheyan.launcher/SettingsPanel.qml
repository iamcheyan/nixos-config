import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property QtObject bar: null
  property var hostWidget: null
  property Item anchorItem: null
  property var settings: ({})
  property bool opened: false
  property int columns: 8
  property int rows: 4
  property int iconSize: 48
  property int fontSize: 14

  readonly property int automaticColumns: Math.max(1, Math.floor(
    (Math.min(Screen.width * 0.80, 1260) - 40) / 140))
  readonly property int automaticRows: 4
  readonly property int displayedColumns: root.columns > 0 ? root.columns : root.automaticColumns
  readonly property int displayedRows: root.rows > 0 ? root.rows : root.automaticRows

  readonly property string stateFile: Quickshell.env("HOME")
    + "/.local/state/iamcheyan-launcher/layout.json"

  function bounded(value, fallback, minimum, maximum) {
    var number = parseInt(value, 10)
    if (isNaN(number)) return fallback
    return Math.max(minimum, Math.min(maximum, number))
  }

  function readSettings() {
    root.columns = bounded(root.setting("columns", root.columns), 8, 0, 20)
    root.rows = bounded(root.setting("rows", root.rows), 4, 0, 10)
    root.iconSize = bounded(root.setting("iconSize", root.iconSize), 48, 24, 96)
    root.fontSize = bounded(root.setting("fontSize", root.fontSize), 14, 10, 24)
  }

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function open() {
    root.readSettings()
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function saveStateFile() {
    var payload = JSON.stringify({
      columns: root.columns,
      rows: root.rows,
      iconSize: root.iconSize,
      fontSize: root.fontSize
    })
    Util.execDetached("mkdir -p "
      + Util.shellQuote(Quickshell.env("HOME") + "/.local/state/iamcheyan-launcher")
      + " && printf %s " + Util.shellQuote(payload)
      + " > " + Util.shellQuote(root.stateFile))
  }

  function persist() {
    var entry = { id: "iamcheyan.launcher" }
    for (var key in root.settings) {
      if (key !== "id") entry[key] = root.settings[key]
    }
    entry.columns = root.columns
    entry.rows = root.rows
    entry.iconSize = root.iconSize
    entry.fontSize = root.fontSize
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget)
      root.hostWidget.settings = entry
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline("iamcheyan.launcher", entry)
    root.saveStateFile()
  }

  function commit(kind, value) {
    if (kind === "columns") root.columns = bounded(value, 0, 1, 20)
    else if (kind === "rows") root.rows = bounded(value, 0, 1, 10)
    else if (kind === "iconSize") root.iconSize = bounded(value, 52, 24, 96)
    else root.fontSize = bounded(value, 14, 10, 24)
    root.persist()
  }

  onSettingsChanged: root.readSettings()

  FileView {
    id: stateFileView
    path: root.stateFile
    printErrors: false
    onLoaded: {
      if (root.settings && root.settings.columns !== undefined) return
      try {
        var saved = JSON.parse(text())
        root.columns = root.bounded(saved.columns, 8, 0, 20)
        root.rows = root.bounded(saved.rows, 4, 0, 10)
        root.iconSize = root.bounded(saved.iconSize, 48, 24, 96)
        root.fontSize = root.bounded(saved.fontSize, 14, 10, 24)
      } catch (error) {
        root.columns = 8
        root.rows = 4
        root.iconSize = 48
        root.fontSize = 14
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    Column {
      id: content
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "Icon layout settings"
        color: Color.popups.text
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: root.fontSize + 4
        font.bold: true
      }

      Text {
        text: "0 means automatic sizing"
        color: Util.alpha(Color.popups.text, 0.62)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Math.max(10, root.fontSize - 2)
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(16)

        Text {
          Layout.fillWidth: true
          text: "Columns"
          color: Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: root.fontSize
        }

        NumberField {
          label: ""
          from: 1
          to: 20
          value: root.displayedColumns
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: root.fontSize
          onModified: function(value) { root.commit("columns", value) }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(16)

        Text {
          Layout.fillWidth: true
          text: "Rows"
          color: Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: root.fontSize
        }

        NumberField {
          label: ""
          from: 1
          to: 10
          value: root.displayedRows
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: root.fontSize
          onModified: function(value) { root.commit("rows", value) }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(16)

        Text {
          Layout.fillWidth: true
          text: "Icon size"
          color: Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: root.fontSize
        }

        NumberField {
          label: ""
          from: 24
          to: 96
          stepSize: 4
          value: root.iconSize
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: root.fontSize
          onModified: function(value) { root.commit("iconSize", value) }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(16)

        Text {
          Layout.fillWidth: true
          text: "Interface font size"
          color: Color.popups.text
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: root.fontSize
        }

        NumberField {
          label: ""
          from: 10
          to: 24
          value: root.fontSize
          foreground: Color.popups.text
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: root.fontSize
          onModified: function(value) { root.commit("fontSize", value) }
        }
      }

      Button {
        text: "Reset layout to defaults"
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        fontSize: root.fontSize
        onClicked: {
          root.columns = 8
          root.rows = 4
          root.iconSize = 48
          root.fontSize = 14
          root.persist()
        }
      }
    }
  }
}
