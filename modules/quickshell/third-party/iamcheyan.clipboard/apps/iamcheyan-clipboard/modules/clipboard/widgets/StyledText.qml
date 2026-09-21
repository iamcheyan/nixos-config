pragma ComponentBehavior: Bound
import QtQuick

Text {
    id: root

    // NativeRendering can leave stale glyphs behind when a ListView delegate
    // is populated or reused asynchronously, especially with CJK fallback
    // fonts. QtRendering repaints the complete glyph run reliably.
    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter

    font {
        hintingPreference: Font.PreferDefaultHinting
        family: ClipboardStyle.fontFamily
        pixelSize: ClipboardStyle.fontPixelSmall
    }
    color: ClipboardStyle.fg
    linkColor: ClipboardStyle.accent
}
