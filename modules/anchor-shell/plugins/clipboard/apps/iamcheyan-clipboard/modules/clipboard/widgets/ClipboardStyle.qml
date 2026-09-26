pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string themePath: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/labwc/clipboard-theme.json`
    // Keep the original menu structure, but use the same restrained popup
    // palette as Omarchy's native panels: one surface, a quiet border, and
    // the accent only for selection/focus.
    readonly property color fg: "#e7e7e7"
    readonly property color dim: "#b0b0b0"
    readonly property color muted: "#7f7f7f"
    readonly property color bg: themeJson.background || "#0d0f10"
    readonly property color panel: "#151719"
    readonly property color surface: "#1b1e20"
    readonly property color surfaceHover: "#24282b"
    readonly property color surfaceSelected: Qt.rgba(accent.r, accent.g, accent.b, 0.18)
    readonly property color line: "#3a3f43"
    readonly property color separator: "#2b3033"
    readonly property color accent: themeJson.primary || "#d7d7d7"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.18)
    readonly property int radius: 10

    readonly property string fontFamily: "MesloLGS Nerd Font"
    readonly property int fontPixelSmall: 12

    readonly property string cliphistDecode: (Quickshell.env("HOME") ?? "") + "/.cache/media/cliphist"

    FileView {
        id: themeFile
        path: root.themePath
        watchChanges: true
        // The theme file is optional on first launch. The fallback palette is
        // intentional, so do not emit a noisy FileView warning for absence.
        printErrors: false

        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn(`[ClipboardStyle] Failed to load ${root.themePath}: ${error}`);
        }

        JsonAdapter {
            id: themeJson
            property string primary: "#eeeeee"
            property string background: "#050505"
            property string backgroundText: "#f4f4f4"
        }
    }

    function cleanCliphistEntry(str: string): string {
        const text = String(str).replace(/^\d+\t/, "");
        // Normalize only the presentation. The original clipboard payload
        // remains untouched for preview and paste.
        return text.split(/\r?\n/).map(line => line.replace(/^\s+/, "")).join("\n").trim();
    }
}
