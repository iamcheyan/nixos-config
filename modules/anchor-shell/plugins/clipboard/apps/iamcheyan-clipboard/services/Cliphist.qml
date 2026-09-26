pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property int maxEntries: 300
    property var entries: []
    property var nativeEntries: []
    property string lastPasteEntry: ""
    property double lastPasteAt: 0
    readonly property string historyPath: (Quickshell.env("XDG_STATE_HOME") || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/labwc/clipboard-history.json"
    readonly property string pasteFileTool: Qt.resolvedUrl("../../../backend/clipboard-paste-file").toString().replace("file://", "")
    readonly property string pasteTextTool: Qt.resolvedUrl("../../../backend/clipboard-paste-text").toString().replace("file://", "")
    readonly property string pathPasteTool: Qt.resolvedUrl("../../../bin/iamcheyan-clipboard-paste-path").toString().replace("file://", "")

    function pseudo(entry, index) {
        if (entry.type === "image") return index + "\t[[ native image " + String(entry.mime || "image/png") + " ]] " + String(entry.path || "")
        return index + "\t" + String(entry.text || "")
    }
    function hasMeaningfulText(value) {
        const text = String(value || "");
        // Keep letters, numbers, symbols such as emoji, and CJK characters;
        // discard entries made only from whitespace or punctuation marks.
        return text.replace(/[\s.,，。!?！？;；:：、…·'"`~\-_=+()[\]{}<>/\\|]+/g, "").length > 0;
    }
    function parse(raw) {
        try { const value = JSON.parse(String(raw || "[]")); return Array.isArray(value) ? value.filter(e => e && (e.type === "text" || e.type === "image")) : [] }
        catch (error) { return [] }
    }
    function refresh() { historyFile.reload() }
    function rebuild(raw) {
        root.nativeEntries = root.parse(raw)
        root.entries = root.nativeEntries.slice(0, root.maxEntries)
            .map((e, i) => root.pseudo(e, i))
            .filter((entry) => root.entryIsImage(entry) || root.hasMeaningfulText(root.entryText(entry)))
        root.changed()
    }
    function indexFor(entry) { const match = String(entry || "").match(/^(\d+)\t/); return match ? Number(match[1]) : -1 }
    function nativeFor(entry) { const index = root.indexFor(entry); return index >= 0 && index < root.nativeEntries.length ? root.nativeEntries[index] : null }
    function entryIsImage(entry) { const value = root.nativeFor(entry); return value && value.type === "image" }
    function entryPayload(entry) { return String(entry || "").replace(/^\s*\S+\s+/, "") }
    function entryText(entry) { const value = root.nativeFor(entry); return value && value.type === "text" ? String(value.text || "") : "" }
    function imagePath(entry) { const value = root.nativeFor(entry); return value && value.type === "image" ? String(value.path || "") : "" }
    function fuzzyQuery(query) { const needle = String(query || "").trim().toLowerCase(); return needle ? root.entries.filter(e => root.entryPayload(e).toLowerCase().indexOf(needle) >= 0) : root.entries }
    function claimPaste(entry) { const now = Date.now(); if (entry === root.lastPasteEntry && now - root.lastPasteAt < 900) return false; root.lastPasteEntry = entry; root.lastPasteAt = now; return true }
    function pasteSmart(entry) {
        if (!root.claimPaste(entry)) return;
        const index = root.indexFor(entry);
        if (index < 0 || index >= root.nativeEntries.length) return;

        const value = root.nativeEntries[index];
        if (value && value.type === "image" && value.path) {
            // Images must be copied with the file helper so their binary data
            // and MIME type are restored to the clipboard before pasting.
            Quickshell.execDetached([
                root.pasteFileTool,
                String(value.mime || "image/png"),
                String(value.path)
            ]);
            return;
        }

        if (value && value.type === "text")
            Quickshell.execDetached([root.pasteTextTool, "--shift-insert", "--history-index", String(index)]);
    }
    // The image-row arrow is the explicit text fallback: copy the native
    // image file path as text, then paste it in one operation.
    function pasteImagePath(entry) {
        if (!root.claimPaste(entry)) return;
        const index = root.indexFor(entry);
        if (index < 0 || index >= root.nativeEntries.length) return;
        const value = root.nativeEntries[index];
        if (value && value.type === "image" && value.path)
            Quickshell.execDetached([root.pathPasteTool, String(value.path)]);
    }
    function deleteEntry(entry) { const index = root.indexFor(entry); if (index < 0 || index >= root.nativeEntries.length) return; const next = root.nativeEntries.slice(); next.splice(index, 1); historyFile.setText(JSON.stringify(next, null, 2) + "\n") }
    function wipe() { historyFile.setText("[]\n") }
    function setDialogVisible(visible) { if (visible) root.refresh() }
    signal changed()

    FileView {
        id: historyFile
        path: root.historyPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.rebuild(text())
        onFileChanged: reload()
        onLoadFailed: { root.nativeEntries = []; root.entries = []; root.changed() }
    }
    IpcHandler { target: "cliphistService"; function update(): void { root.refresh() } }
    Component.onCompleted: root.refresh()
}
