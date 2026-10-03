import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tetsuya.ai-usagebar"

  property string label: "AI"
  property string usageLabel: "AI"
  property string tip: "AI usage is not available yet"
  property string baseTip: "AI usage is not available yet"
  property var quotaProviders: []
  property var summaryItems: []
  property var quotaUpdatedAt: null
  property bool quotaPopupOpen: false
  property bool hasReport: false

  function refresh() {
    if (!usageProc.running) usageProc.running = true
    if (!quotaProc.running) quotaProc.running = true
  }

  function openDashboard() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation ai-usagebar-tui")
  }

  function updateTooltip() { root.tip = "" }

  function resetLabel(value) {
    if (value === undefined || value === null || value === "") return ""
    var date = null
    if (typeof value === "number" || /^\d+(\.\d+)?$/.test(String(value))) {
      var epoch = Number(value)
      if (epoch < 100000000000) epoch *= 1000
      date = new Date(epoch)
    } else {
      date = new Date(String(value))
    }
    if (!date || isNaN(date.getTime())) return String(value).replace("T", " ").replace(/Z$/, "")
    return date.toLocaleString(Qt.locale(), "MM-dd HH:mm")
  }

  function resetEpoch(value) {
    if (value === undefined || value === null || value === "") return 0
    var epoch = null
    if (typeof value === "number" || /^\d+(\.\d+)?$/.test(String(value))) {
      epoch = Number(value)
      if (epoch < 100000000000) epoch *= 1000
    } else {
      epoch = new Date(String(value)).getTime()
    }
    return isFinite(epoch) ? epoch : 0
  }

  function countdown(epoch) {
    if (!epoch) return ""
    var mins = Math.max(0, Math.floor((epoch - Date.now()) / 60000))
    if (mins <= 0) return "now"
    var days = Math.floor(mins / 1440)
    var hours = Math.floor((mins % 1440) / 60)
    var rest = mins % 60
    if (days > 0) return days + "d" + (hours > 0 ? hours + "h" : "")
    if (hours > 0) return hours + "h" + (rest > 0 ? rest + "m" : "")
    return rest + "m"
  }

  function compactCountdown(epoch) {
    return root.countdown(epoch).replace(/(\d+h\d+)m$/, "$1")
  }

  function updateBarLabel() {
    var summaries = []
    var codex = root.quotaProviders.find(function(provider) { return provider.id === "codex" })
    if (codex) {
      var session = codex.buckets.find(function(bucket) { return /primary/i.test(bucket.label) && !/gpt.?reserve/i.test(bucket.label) })
        || codex.buckets.find(function(bucket) { return /primary/i.test(bucket.label) })
      if (session) summaries.push({
        id: "codex", icon: Qt.resolvedUrl("icons/openai.svg"), used: 100 - session.remaining,
        reset: root.compactCountdown(session.resetAt)
      })
    }
    var agy = root.quotaProviders.find(function(provider) { return provider.id === "agy" })
    if (agy) {
      var gemini = agy.buckets.find(function(bucket) { return /gemini.*(5h|5-hour)|5h.*gemini/i.test(bucket.label) })
        || agy.buckets.find(function(bucket) { return /gemini/i.test(bucket.label) })
      if (gemini) summaries.push({
        id: "gemini", icon: Qt.resolvedUrl("icons/gemini.svg"), used: 100 - gemini.remaining,
        reset: root.compactCountdown(gemini.resetAt)
      })
    }
    root.summaryItems = summaries
    root.label = summaries.length ? "" : root.usageLabel
  }

  function plainText(value) {
    var text = String(value || "")
      .replace(/<[^>]*>/g, "")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"")
      .replace(/&#39;/g, "'")
    var result = ""
    for (var i = 0; i < text.length;) {
      var point = text.codePointAt(i)
      var width = point > 0xffff ? 2 : 1
      var isPrivateUse = (point >= 0xe000 && point <= 0xf8ff)
        || (point >= 0xf0000 && point <= 0xffffd)
        || (point >= 0x100000 && point <= 0x10fffd)
      if (!isPrivateUse) result += text.slice(i, i + width)
      i += width
    }
    return result
  }

  function compactTooltip(value) {
    var lines = plainText(value).split("\n")
    var rows = []
    var metricIndex = -1
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
        .replace(/[│┃╭╮╰╯┌┐└┘]/g, "")
        .replace(/[─━█░▒▓]+/g, "")
        .replace(/\s+/g, " ")
        .trim()
      if (/^Credits\b/i.test(line) || /^Reset credits\b/i.test(line)) break
      if (line === "") continue
      if (/^Updated\b/i.test(line)) continue
      if (rows.length === 0) {
        rows.push(line)
        continue
      }
      if (/^Resets in\b/i.test(line)) {
        if (metricIndex >= 0) rows[metricIndex] += " · " + line
        continue
      }
      if (/\d{1,3}%/.test(line)) {
        if (metricIndex >= 0) rows[metricIndex] += " · " + line
        continue
      }
      if (rows.length < 5) {
        rows.push(line)
        metricIndex = rows.length - 1
      }
    }
    return rows.join("\n") || "AI provider usage"
  }

  function svcQuotaTooltip(data) {
    var providers = [
      ["codex", "Codex CLI"], ["agy", "Antigravity"], ["grok", "Grok CLI"],
      ["kiro", "Kiro"], ["cursor", "Cursor"], ["dim", "dim"]
    ]
    var rows = []
    for (var i = 0; i < providers.length; i++) {
      var provider = providers[i]
      var report = data[provider[0]]
      if (!report || report.ok === false) continue
      var buckets = []
      var providerDetail = ""
      if (provider[0] === "agy") {
        var groups = (report.quota && report.quota.groups) || []
        for (var g = 0; g < groups.length; g++) {
          var group = groups[g]
          for (var b = 0; b < (group.buckets || []).length; b++) {
            var bucket = group.buckets[b]
            if (bucket.remainingFraction === undefined) continue
            buckets.push({
              label: (group.displayName || "Gemini") + " · " + (bucket.bucketId || "quota"),
              remaining_pct: Math.round(Number(bucket.remainingFraction) * 100),
              reset: bucket.resetTime || ""
            })
          }
        }
      } else if (provider[0] === "codex") {
        var limits = (report.rateLimits || {}).rateLimitsByLimitId || {}
        for (var key in limits) {
          var limit = limits[key]
          for (var tag of ["primary", "secondary"]) {
            var item = limit[tag]
            if (!item || item.usedPercent === undefined) continue
            buckets.push({ label: (limit.limitName || limit.limitId || key) + " · " + tag,
              remaining_pct: 100 - Number(item.usedPercent), reset: item.resetsAt || "" })
          }
        }
        var summary = ((report.usage || {}).summary) || {}
        var tokenStats = []
        if (summary.weeklyTokens !== undefined) tokenStats.push("7d " + root.formatCount(summary.weeklyTokens))
        if (summary.lifetimeTokens !== undefined) tokenStats.push("lifetime " + root.formatCount(summary.lifetimeTokens))
        providerDetail = tokenStats.join(" · ")
      } else if (provider[0] === "grok") {
        var cfg = (report.billing || {}).config || {}
        if (cfg.creditUsagePercent !== undefined) buckets.push({label:"Credits",
          remaining_pct:100-Number(cfg.creditUsagePercent), reset:(cfg.currentPeriod || {}).end || ""})
        var prepaid = ((cfg.prepaidBalance || {}).val)
        if (prepaid !== undefined && prepaid !== null) providerDetail = "Prepaid balance " + prepaid
      } else if (provider[0] === "kiro") {
        var usage = report.usage || {}
        for (var k = 0; k < (usage.usageBreakdownList || []).length; k++) {
          var u = usage.usageBreakdownList[k]
          if (Number(u.usageLimit) > 0) buckets.push({label:u.displayName || u.resourceType || "Usage",
            remaining_pct:100-Number(u.currentUsage)/Number(u.usageLimit)*100, reset:""})
        }
      } else if (provider[0] === "cursor") {
        var pu = ((report.usage || {}).planUsage) || {}
        for (var pair of [["Included", "totalPercentUsed"], ["Auto", "autoPercentUsed"], ["API", "apiPercentUsed"]]) {
          if (pu[pair[1]] !== undefined) buckets.push({label:pair[0], remaining_pct:100-Number(pu[pair[1]]), reset:""})
        }
      } else if (provider[0] === "dim") {
        var credits = report.credits || {}
        var total = Number(credits.total_units || 0)
        if (report.ok && total > 0) {
          var remaining = Number(credits.remaining_units || 0)
          var used = Number(credits.used_units || 0)
          buckets.push({label:"Credits", remaining_pct:100*remaining/total,
            reset:report.term_end || "", detail:used.toLocaleString() + " used / " + total.toLocaleString() + " total"})
          var subscription = credits.subscription || {}
          var subTotal = Number(subscription.total_units || 0)
          if (subTotal > 0 && (subTotal !== total || Number(subscription.remaining_units) !== remaining)) {
            buckets.push({label:"Subscription", remaining_pct:100*Number(subscription.remaining_units || 0)/subTotal,
              reset:subscription.expires_at || report.term_end || "",
              detail:Number(subscription.used_units || 0).toLocaleString() + " used / " + subTotal.toLocaleString() + " total"})
          }
          for (var a = 0; a < (credits.addon || []).length; a++) {
            var addon = credits.addon[a]
            var addonTotal = Number(addon.total_units || 0)
            if (addonTotal > 0) buckets.push({label:"Add-on " + (a + 1),
              remaining_pct:100*Number(addon.remaining_units || 0)/addonTotal,
              reset:addon.expires_at || "",
              detail:Number(addon.used_units || 0).toLocaleString() + " used / " + addonTotal.toLocaleString() + " total"})
          }
          providerDetail = report.subscription_status ? "Subscription " + report.subscription_status : ""
        }
      }
      if (!buckets.length) continue
      var cleanBuckets = []
      for (var j = 0; j < buckets.length; j++) {
        var bucket = buckets[j]
        var pct = Math.max(0, Math.min(100, Math.round(Number(bucket.remaining_pct))))
        cleanBuckets.push({ label: bucket.label, remaining: pct, reset: root.resetLabel(bucket.reset), resetAt: root.resetEpoch(bucket.reset), detail: bucket.detail || "" })
      }
      rows.push({ id: provider[0], name: provider[1], detail: providerDetail, buckets: cleanBuckets })
    }
    return rows
  }

  function formatCount(value) {
    var n = Number(value)
    if (!isFinite(n)) return String(value)
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(0) + "K"
    return String(Math.round(n))
  }

  Process {
    id: usageProc
    command: ["ai-usagebar", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var report = JSON.parse(String(text || ""))
          root.usageLabel = root.plainText(report.text || "AI")
          root.updateBarLabel()
          root.baseTip = root.compactTooltip(report.tooltip || "")
          root.updateTooltip()
          root.hasReport = true
        } catch (error) {
          root.usageLabel = "AI"
          root.updateBarLabel()
          root.baseTip = "Could not read AI usage report"
          root.updateTooltip()
          root.hasReport = false
        }
      }
    }
  }

  Process {
    id: quotaProc
    command: ["bash", Quickshell.env("HOME") + "/.config/agent/tools/agent-quota.sh", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.quotaProviders = root.svcQuotaTooltip(JSON.parse(String(text || "{}")))
          root.quotaUpdatedAt = new Date()
          root.updateBarLabel()
          root.updateTooltip()
        } catch (error) {
          root.quotaProviders = []
        }
      }
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.updateBarLabel()
  }

  implicitWidth: summaryItems.length ? compactSummary.implicitWidth + Style.space(18) : button.implicitWidth
  implicitHeight: button.implicitHeight

  Row {
    id: compactSummary
    anchors.centerIn: parent
    spacing: Style.space(10)

    Repeater {
      model: root.summaryItems

      delegate: Row {
        required property var modelData
        spacing: Style.space(4)
        readonly property color usageColor: modelData.used >= 80 ? "#f0444c" : modelData.used >= 50 ? "#f59e0b" : "#22c55e"

        Image {
          width: Style.space(18)
          height: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter
          source: modelData.icon
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
        }

        Text {
          text: modelData.used + "%"
          color: parent.usageColor
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          width: Style.space(26)
          height: Style.space(3)
          radius: height / 2
          color: Qt.rgba(1, 1, 1, 0.16)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            width: parent.width * modelData.used / 100
            height: parent.height
            radius: parent.radius
            color: parent.parent.usageColor
          }
        }

        Text {
          text: modelData.reset
          visible: text !== ""
          color: Color.foreground
          opacity: 0.72
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    labelVisible: root.summaryItems.length === 0
    hasVisualContent: root.summaryItems.length > 0 || root.label !== ""
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: ""
    onPressed: root.openDashboard()
  }

  HoverHandler {
    id: anchorHover
    onHoveredChanged: {
      if (hovered) {
        popupCloseTimer.stop()
        root.quotaPopupOpen = true
      } else {
        popupCloseTimer.restart()
      }
    }
  }

  Timer {
    id: popupCloseTimer
    interval: 220
    onTriggered: if (!quotaPopup.containsMouse && !anchorHover.hovered) root.quotaPopupOpen = false
  }

  PopupCard {
    id: quotaPopup
    anchorItem: root
    bar: root.bar
    owner: root
    triggerMode: "hover"
    open: root.quotaPopupOpen
    contentWidth: quotaPopup.fittedContentWidth(Style.space(360), Style.space(480))
    contentHeight: quotaPopup.fittedContentHeight(quotaColumn.implicitHeight)
    onContainsMouseChanged: {
      if (containsMouse) popupCloseTimer.stop()
      else popupCloseTimer.restart()
    }

    Flickable {
      id: scroll
      anchors.fill: parent
      clip: true
      contentWidth: width
      contentHeight: quotaColumn.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: quotaColumn
        width: scroll.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "AI usage"
            color: Color.popups.text
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            text: quotaProc.running && !root.quotaUpdatedAt
              ? "Loading…"
              : root.quotaUpdatedAt
                ? "Updated " + root.quotaUpdatedAt.toLocaleTimeString(Qt.locale(), "HH:mm")
                : "No quota data"
            color: Color.popups.text
            opacity: 0.62
            font.family: root.bar ? root.bar.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Repeater {
          model: root.quotaProviders

          delegate: Column {
            required property var modelData
            width: quotaColumn.width
            spacing: Style.space(7)

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.1) }

            Text {
              text: modelData.name
              color: Color.popups.text
              font.family: root.bar ? root.bar.fontFamily : "sans-serif"
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              visible: modelData.detail !== ""
              text: modelData.detail
              color: Color.popups.text
              opacity: 0.62
              font.family: root.bar ? root.bar.fontFamily : "sans-serif"
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: modelData.buckets

              delegate: Column {
                required property var modelData
                width: quotaColumn.width
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    text: modelData.label
                    color: Color.popups.text
                    font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    width: parent.width - pctLabel.implicitWidth - resetLabelText.implicitWidth - Style.space(16)
                  }

                  Text {
                    id: resetLabelText
                    text: modelData.reset
                    visible: text !== ""
                    color: Color.popups.text
                    opacity: 0.58
                    font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: pctLabel
                    text: modelData.remaining + "%"
                    color: modelData.remaining <= 15 ? "#f0444c" : modelData.remaining <= 40 ? "#f59e0b" : "#22c55e"
                    font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Style.space(7)
                  radius: height / 2
                  color: Qt.rgba(1, 1, 1, 0.11)

                  Rectangle {
                    width: parent.width * modelData.remaining / 100
                    height: parent.height
                    radius: parent.radius
                    color: modelData.remaining <= 15 ? "#f0444c" : modelData.remaining <= 40 ? "#f59e0b" : "#22c55e"
                  }
                }

                Text {
                  visible: modelData.detail !== ""
                  text: modelData.detail || ""
                  color: Color.popups.text
                  opacity: 0.58
                  font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }

  }
}
