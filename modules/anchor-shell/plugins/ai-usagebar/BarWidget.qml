import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "tetsuya.ai-usagebar"

  property string label: ""
  property string usageLabel: ""
  property string tip: "AI usage is not available yet"
  property string baseTip: "AI usage is not available yet"
  property var quotaProviders: []
  property var summaryItems: []
  property var resetInventories: []
  property var quotaUpdatedAt: null
  property var resetCreditsUpdatedAt: null
  property string resetInventoryError: ""
  property int clockTick: Date.now()
  property bool quotaPopupOpen: false
  property bool hasReport: false
  property bool usageLoaded: false
  property bool quotaLoaded: false
  property bool resetCreditsLoaded: false
  readonly property bool initialLoadComplete: usageLoaded && quotaLoaded && resetCreditsLoaded
  readonly property int totalResetCredits: {
    var total = 0
    for (var i = 0; i < resetInventories.length; i++)
      total += Math.max(0, Number(resetInventories[i].available || 0))
    return total
  }
  readonly property var nextResetCredit: {
    var earliest = null
    for (var i = 0; i < resetInventories.length; i++) {
      var inventory = resetInventories[i]
      if (Number(inventory.available || 0) <= 0) continue
      for (var j = 0; j < inventory.credits.length; j++) {
        var credit = inventory.credits[j]
        if (credit.expiresAt > 0 && (!earliest || credit.expiresAt < earliest.expiresAt))
          earliest = { expiresAt: credit.expiresAt }
      }
    }
    return earliest
  }
  readonly property color resetCreditColor: nextResetCredit
    && nextResetCredit.expiresAt - clockTick < 86400000 ? "#f0444c" : "#f59e0b"

  function refresh() {
    if (!usageProc.running) usageProc.running = true
    if (!quotaProc.running) quotaProc.running = true
    if (!resetCreditsProc.running) resetCreditsProc.running = true
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
    return date.toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm")
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

  function resetInventoryFromReport(report) {
    var resetCapable = { anthropic: true, openai: true, supergrok: true }
    var entries = Array.isArray(report.entries) ? report.entries : []
    var inventories = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var id = String(entry.id || entry.name || "").toLowerCase()
      if (!resetCapable[id]) continue
      var resetCredits = entry.reset_credits || null
      var credits = []
      var rawCredits = resetCredits && Array.isArray(resetCredits.credits) ? resetCredits.credits : []
      for (var j = 0; j < rawCredits.length; j++) {
        var expiresAt = root.resetEpoch(rawCredits[j].expires_at)
        credits.push({
          title: String(rawCredits[j].title || "Reset credit"),
          expiresAt: expiresAt,
          expiresLabel: expiresAt ? root.resetLabel(expiresAt) : "Expiry unavailable"
        })
      }
      credits.sort(function(a, b) {
        if (!a.expiresAt) return 1
        if (!b.expiresAt) return -1
        return a.expiresAt - b.expiresAt
      })
      var failed = entry.status === "error" && !resetCredits
      inventories.push({
        id: id,
        name: String(entry.display_name || entry.short_name || entry.name || id),
        available: resetCredits ? Number(resetCredits.available || 0) : (failed ? -1 : 0),
        credits: credits,
        unlisted: resetCredits ? Math.max(0, Number(resetCredits.available || 0) - credits.length) : 0,
        stale: Boolean(entry.stale),
        failed: failed
      })
    }
    return inventories
  }

  function resetCreditsForProvider(id) {
    // The quota view calls these products Codex, Antigravity, and Grok CLI,
    // while the reset-credit endpoint uses their underlying account names.
    var inventoryId = id === "codex" ? "openai"
      : id === "agy" ? "anthropic"
      : id === "grok" ? "supergrok" : ""
    if (!inventoryId) return null
    for (var i = 0; i < resetInventories.length; i++) {
      if (resetInventories[i].id === inventoryId
          && Number(resetInventories[i].available || 0) > 0)
        return resetInventories[i]
    }
    return null
  }

  function resetExpiryText(epoch) {
    if (!epoch) return "Expiry unavailable"
    return epoch <= clockTick ? "Expired" : "in " + root.countdown(epoch)
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
      var session = codex.buckets.find(function(bucket) {
        return /(?:primary|\b5h\b)/i.test(bucket.label) && !/gpt.?reserve/i.test(bucket.label)
      }) || codex.buckets.find(function(bucket) { return /(?:primary|\b5h\b)/i.test(bucket.label) })
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
    // The generic CLI text is not useful in the bar; keep it icon-and-metrics
    // only, and avoid showing partial provider results during the first load.
    root.label = ""
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
            var windowMins = Number(item.windowDurationMins || 0)
            var windowLabel = windowMins >= 10080 ? Math.round(windowMins / 10080) + "w"
              : windowMins >= 1440 ? Math.round(windowMins / 1440) + "d"
              : windowMins >= 60 ? Math.round(windowMins / 60) + "h"
              : tag === "primary" ? "5h" : "weekly"
            buckets.push({ label: (limit.limitName || limit.limitId || key) + " · " + windowLabel,
              remaining_pct: 100 - Number(item.usedPercent), reset: item.resetsAt || "" })
          }
        }
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
            remaining_pct:100-Number(u.currentUsage)/Number(u.usageLimit)*100, reset:usage.nextDateReset || ""})
        }
      } else if (provider[0] === "cursor") {
        var pu = ((report.usage || {}).planUsage) || {}
        for (var pair of [["Included", "totalPercentUsed"], ["Auto", "autoPercentUsed"], ["API", "apiPercentUsed"]]) {
          if (pu[pair[1]] !== undefined) buckets.push({label:pair[0], remaining_pct:100-Number(pu[pair[1]]),
            reset:report.billingCycleEnd || (report.usage || {}).billingCycleEnd || ""})
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
          root.updateBarLabel()
          root.baseTip = "Could not read AI usage report"
          root.updateTooltip()
          root.hasReport = false
        }
        root.usageLoaded = true
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
        root.quotaLoaded = true
      }
    }
  }

  Process {
    id: resetCreditsProc
    command: ["ai-usagebar", "usage", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var report = JSON.parse(String(text || "{}"))
          root.resetInventories = root.resetInventoryFromReport(report)
          root.resetCreditsUpdatedAt = new Date()
          root.resetInventoryError = ""
        } catch (error) {
          root.resetInventoryError = "Reset credit details could not be refreshed"
        }
        root.resetCreditsLoaded = true
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
    onTriggered: {
      root.clockTick = Date.now()
      root.updateBarLabel()
    }
  }

  implicitWidth: summaryItems.length > 0 || totalResetCredits > 0
    ? compactSummary.implicitWidth + Style.space(18) : button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: initialLoadComplete && (summaryItems.length > 0 || totalResetCredits > 0)

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

    Rectangle {
      visible: root.totalResetCredits > 0
      implicitWidth: resetBadge.implicitWidth + Style.space(14)
      implicitHeight: resetBadge.implicitHeight + Style.space(6)
      width: implicitWidth
      height: implicitHeight
      radius: height / 2
      color: Qt.rgba(root.resetCreditColor.r, root.resetCreditColor.g,
        root.resetCreditColor.b, 0.16)
      border.width: Style.space(1)
      border.color: Qt.rgba(root.resetCreditColor.r, root.resetCreditColor.g,
        root.resetCreditColor.b, 0.72)
      anchors.verticalCenter: parent.verticalCenter

      Row {
        id: resetBadge
        anchors.centerIn: parent
        spacing: Style.space(4)

        Text {
          text: "↻"
          color: root.resetCreditColor
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Text {
          text: root.totalResetCredits
          color: root.resetCreditColor
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          visible: root.nextResetCredit !== null
          text: root.nextResetCredit ? "· " + root.countdown(root.nextResetCredit.expiresAt) : ""
          color: root.resetCreditColor
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
        }
      }
    }

  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    labelVisible: false
    hasVisualContent: root.summaryItems.length > 0 || root.totalResetCredits > 0
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
              width: quotaColumn.width
              wrapMode: Text.Wrap
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
                    text: modelData.reset ? "↻ " + modelData.reset : ""
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

            Rectangle {
              id: resetSection
              readonly property var inventory: root.resetCreditsForProvider(modelData.id)
              visible: inventory !== null
              width: quotaColumn.width
              implicitHeight: resetCard.implicitHeight + Style.space(14)
              height: implicitHeight
              radius: Style.space(6)
              color: Qt.rgba(0.96, 0.62, 0.05, 0.07)
              border.width: Style.space(1)
              border.color: Qt.rgba(0.96, 0.62, 0.05, 0.3)

              Column {
                id: resetCard
                anchors.fill: parent
                anchors.leftMargin: Style.space(9)
                anchors.rightMargin: Style.space(14)
                anchors.topMargin: Style.space(8)
                anchors.bottomMargin: Style.space(8)
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: "↻  RESET CREDITS"
                    color: "#f59e0b"
                    font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: resetSection.inventory
                      ? resetSection.inventory.available + " available" : ""
                    color: Color.popups.text
                    opacity: 0.68
                    font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Repeater {
                  model: resetSection.inventory ? resetSection.inventory.credits : []

                  delegate: Row {
                    required property var modelData
                    width: resetCard.width
                    spacing: Style.space(7)

                    Rectangle {
                      width: Style.space(3)
                      height: Style.space(14)
                      radius: width / 2
                      color: "#f59e0b"
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      text: modelData.title
                      width: Math.max(0, parent.width - expiryText.implicitWidth - Style.space(22))
                      color: Color.popups.text
                      font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      id: expiryText
                      text: modelData.expiresLabel
                      color: Color.popups.text
                      opacity: 0.64
                      font.family: root.bar ? root.bar.fontFamily : "sans-serif"
                      font.pixelSize: Style.font.caption
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }

                Text {
                  visible: resetSection.inventory !== null && resetSection.inventory.unlisted > 0
                  text: resetSection.inventory
                    ? "+ " + resetSection.inventory.unlisted + " more (expiry unavailable)"
                    : ""
                  x: Style.space(10)
                  color: Color.popups.text
                  opacity: 0.6
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
