
pragma ComponentBehavior: Bound
import "widgets"
import "../../services"
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: clipboardDialog

    property bool show: false
    property real cursorGlobalX: 0
    property real cursorGlobalY: 0
    property real screenGlobalX: 0
    property real screenGlobalY: 0
    property var screen: null
    // "cursor" follows the mouse; "bar" anchors to the top-right of the bar.
    property string positionMode: "cursor"
    property real barHeight: 32
    property int keyboardIndex: 0
    property int hoveredIndex: -1
    // Suppress hover-driven selection right after the menu appears. The menu
    // often pops up under the cursor (cursor placement mode); without this
    // guard the item under the cursor steals selection from the first entry.
    // Cleared once the user actually moves the mouse or presses an arrow key.
    property bool hoverSuppressed: false
    property string searchText: ""
    property string debouncedSearch: ""
    property bool previewRequested: false
    property bool embedded: false
    signal dismiss()
    readonly property int edgeMargin: 14
    // Gap constants match BarPopupGeometry (barGap=4, rightGap=4) — kept
    // locally because this separate Quickshell process can't import the
    // shared qs.modules.common.qml types.
    readonly property int barRightMargin: 8
    readonly property int barTopGap: 6
    readonly property int menuWidth: embedded ? 460 : Math.min(460, Math.max(340, width - edgeMargin * 2))
    readonly property int previewWidth: embedded ? 380 : Math.min(380, Math.max(300, width - edgeMargin * 2))
    readonly property int maxVisibleRows: Math.floor(((screen?.height ?? 720) * 0.8 - 80) / 34)
    // Keep a stable row count until the first cliphist data arrives so the
    // menu doesn't jump from empty to full height on show.
    readonly property int stableRows: 6
    readonly property int visibleRows: Math.min(maxVisibleRows, Math.max(1, filteredEntries.length > 0 ? filteredEntries.length : stableRows))
    // Keep the popup tall and stable like the native shell panels instead of
    // shrinking it whenever the history happens to contain only a few items.
    readonly property int menuHeight: Math.max(260, Math.floor((screen?.height ?? 720) * 0.80))
    readonly property var filteredEntries: debouncedSearch.length > 0 ? Cliphist.fuzzyQuery(debouncedSearch) : Cliphist.entries
    readonly property string selectedEntry: keyboardIndex >= 0 && keyboardIndex < filteredEntries.length ? filteredEntries[keyboardIndex] : ""
    readonly property string previewEntry: previewRequested && selectedEntry !== "" ? selectedEntry : ""
    readonly property bool previewIsImage: previewEntry !== "" && Cliphist.entryIsImage(previewEntry)
    readonly property bool previewOnLeft: menuCard.x + menuWidth + 10 + previewWidth > width - edgeMargin
    // Clipboard text is already decoded in the native history model. Keep it
    // in QML instead of sending attacker-controlled content through a shell.
    readonly property string previewText: previewIsImage ? "" : Cliphist.entryText(previewEntry)

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function placeAtCursor() {
        if (!menuCard)
            return;
        const localX = cursorGlobalX - screenGlobalX;
        const localY = cursorGlobalY - screenGlobalY;
        menuCard.x = clamp(localX, edgeMargin, Math.max(edgeMargin, width - menuWidth - edgeMargin));
        menuCard.y = clamp(localY, edgeMargin, Math.max(edgeMargin, height - menuHeight - edgeMargin));
    }

    function placeAtBar() {
        if (!menuCard)
            return;
        // The layer surface has no size until its first commit, so `width`
        // can briefly be 0 right after show — that would clamp the panel to
        // the left edge (clamp(0-460-4, 4, 4) = 4). Fall back to the screen
        // geometry; onWidthChanged re-places once the real width arrives.
        const w = Math.max(width, screen?.width ?? 0) || 1280;
        menuCard.x = clamp(w - menuWidth - barRightMargin, barRightMargin,
            Math.max(barRightMargin, w - menuWidth - barRightMargin));
        menuCard.y = barHeight + barTopGap
    }
    function placeEmbedded() {
        if (!menuCard)
            return;
        // The native anchor positions the whole card. Inside that card the
        // preview stays on the left and the original menu stays on the right.
        menuCard.x = previewWidth + 10;
        menuCard.y = 0;
    }
    function pasteSelected(asPath) {
        if (selectedEntry === "")
            return;
        const entry = selectedEntry;
        clipboardDialog.dismiss();
        if (asPath && Cliphist.entryIsImage(entry))
            Cliphist.pasteImagePath(entry);
        else
            Cliphist.pasteSmart(entry);
    }

    function deleteSelected() {
        if (selectedEntry !== "")
            Cliphist.deleteEntry(selectedEntry);
    }

    onWidthChanged: if (show) place()
    onHeightChanged: if (show) place()
    onPositionModeChanged: if (show) place()
    onBarHeightChanged: if (show && positionMode === "bar") place()

    function place() {
        if (embedded)
            placeEmbedded();
        else if (positionMode === "bar")
            placeAtBar();
        else
            placeAtCursor();
    }

    onVisibleChanged: {
        if (visible) {
            keyboardIndex = 0;
            hoveredIndex = -1;
            hoverSuppressed = true;
            previewRequested = false;
            searchText = "";
            debouncedSearch = "";
            searchDebounce.stop();
            searchField.text = "";
            Cliphist.setDialogVisible(true);
            // Select the first entry by default and reveal its preview once
            // the (async) cliphist list arrives.
            previewDelay.restart();
            // Reset scroll position: the previous session's contentY persists
            // when the dialog reopens within the warmup window (25s). Without
            // this, data arrives after positionViewAtIndex was called with 0
            // items and the list appears at a random scroll offset.
            clipboardList.contentY = 0;
            Qt.callLater(() => {
                place();
                searchField.forceActiveFocus();
            });
        } else {
            Cliphist.setDialogVisible(false);
        }
    }

    Connections {
        target: Cliphist
        function onEntriesChanged() {
            clipboardDialog.keyboardIndex = Math.min(clipboardDialog.keyboardIndex, Math.max(0, clipboardDialog.filteredEntries.length - 1));
            // Reveal the preview for the now-loaded first entry on open.
            if (clipboardDialog.visible && !clipboardDialog.previewRequested && clipboardDialog.keyboardIndex === 0)
                previewDelay.restart();
            // Entries have arrived — ensure the list is scrolled to the top.
            // positionViewAtIndex may have been a no-op on show because the
            // model was still empty; now that data is here, actually position it.
            if (clipboardDialog.visible && clipboardDialog.keyboardIndex === 0 && clipboardList.count > 0)
                Qt.callLater(() => {
                    clipboardList.forceLayout();
                    clipboardList.positionViewAtIndex(0, ListView.Beginning);
                });
        }
    }

    Timer {
        id: previewDelay
        interval: 180
        repeat: false
        onTriggered: clipboardDialog.previewRequested = clipboardDialog.keyboardIndex >= 0
    }

    Timer {
        id: searchDebounce
        interval: 40
        repeat: false
        onTriggered: {
            clipboardDialog.debouncedSearch = clipboardDialog.searchText;
            clipboardDialog.keyboardIndex = 0;
        }
    }

    Rectangle {
        id: menuCard
        width: clipboardDialog.menuWidth
        height: clipboardDialog.menuHeight
        color: ClipboardStyle.panel
        border.color: ClipboardStyle.line
        border.width: 1
        radius: ClipboardStyle.radius
        clip: true
        focus: true

            Keys.onPressed: event => {
            if (event.key === Qt.Key_Down) {
                event.accepted = true;
                clipboardDialog.hoverSuppressed = false;
                clipboardDialog.keyboardIndex = Math.min(clipboardDialog.keyboardIndex + 1, clipboardDialog.filteredEntries.length - 1);
                clipboardDialog.previewRequested = false;
                previewDelay.restart();
            } else if (event.key === Qt.Key_Up) {
                event.accepted = true;
                clipboardDialog.hoverSuppressed = false;
                clipboardDialog.keyboardIndex = Math.max(0, clipboardDialog.keyboardIndex - 1);
                clipboardDialog.previewRequested = false;
                previewDelay.restart();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                event.accepted = true;
                pasteSelected((event.modifiers & Qt.ControlModifier) !== 0);
            } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                event.accepted = true;
                deleteSelected();
            } else if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                dismiss();
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top Padded胶囊搜索栏 (Maccy Style)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 48

                // Moving the header only affects this invocation. The next
                // open calls place() and restores the active placement.
                // Dragging is disabled in bar mode (anchored popup).
                DragHandler {
                    enabled: clipboardDialog.positionMode !== "bar"
                    target: menuCard
                    acceptedButtons: Qt.LeftButton
                    xAxis.minimum: clipboardDialog.edgeMargin
                    xAxis.maximum: Math.max(clipboardDialog.edgeMargin, clipboardDialog.width - menuCard.width - clipboardDialog.edgeMargin)
                    yAxis.minimum: clipboardDialog.edgeMargin
                    yAxis.maximum: Math.max(clipboardDialog.edgeMargin, clipboardDialog.height - menuCard.height - clipboardDialog.edgeMargin)
                }

                Rectangle {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 10
                        topMargin: 10
                        bottomMargin: 6
                    }
                    radius: 6
                    color: ClipboardStyle.surface
                    border.width: 1
                    border.color: ClipboardStyle.line

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        StyledText {
                            text: "search"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 16
                            color: ClipboardStyle.dim
                        }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            color: ClipboardStyle.fg
                            selectionColor: ClipboardStyle.accent
                            selectedTextColor: ClipboardStyle.bg
                            font.family: ClipboardStyle.fontFamily
                            font.pixelSize: 13
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            onTextChanged: {
                                clipboardDialog.searchText = text;
                                searchDebounce.restart();
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Down) {
                                    event.accepted = true;
                                    clipboardDialog.hoverSuppressed = false;
                                    clipboardDialog.keyboardIndex = Math.min(clipboardDialog.keyboardIndex + 1, clipboardDialog.filteredEntries.length - 1);
                                    clipboardDialog.previewRequested = false;
                                    previewDelay.restart();
                                } else if (event.key === Qt.Key_Up) {
                                    event.accepted = true;
                                    clipboardDialog.hoverSuppressed = false;
                                    clipboardDialog.keyboardIndex = Math.max(0, clipboardDialog.keyboardIndex - 1);
                                    clipboardDialog.previewRequested = false;
                                    previewDelay.restart();
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    event.accepted = true;
                                    clipboardDialog.pasteSelected((event.modifiers & Qt.ControlModifier) !== 0);
                                } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true;
                                    clipboardDialog.deleteSelected();
                                } else if (event.key === Qt.Key_Escape) {
                                    event.accepted = true;
                                    clipboardDialog.dismiss();
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.text.length === 0
                                text: "Type to search..."
                                color: ClipboardStyle.muted
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }

            ListView {
                id: clipboardList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(120, clipboardDialog.menuHeight - 48 - 32)
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: filteredEntries }

                delegate: ClipboardItem {
                    required property string modelData
                    required property int index
                    entry: modelData
                    itemIndex: index
                    width: clipboardList.width
                    selected: clipboardDialog.keyboardIndex === index
                    onItemClicked: clipboardDialog.dismiss()
                    onPasteAsPathRequested: entry => {
                        clipboardDialog.dismiss();
                        Cliphist.pasteImagePath(entry);
                    }
                    onMouseMoved: clipboardDialog.hoverSuppressed = false
                    onHoveredChanged: hovered => {
                        if (hovered) {
                            if (clipboardDialog.hoverSuppressed)
                                return;
                            clipboardDialog.keyboardIndex = index;
                            clipboardDialog.hoveredIndex = index;
                            clipboardDialog.previewRequested = false;
                            previewDelay.restart();
                        } else if (clipboardDialog.hoveredIndex === index) {
                            previewDelay.stop();
                            clipboardDialog.hoveredIndex = -1;
                            clipboardDialog.previewRequested = false;
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: clipboardList.count === 0
                    text: clipboardDialog.searchText.length > 0 ? "No matches" : "Clipboard is empty"
                    color: ClipboardStyle.dim
                    font.pixelSize: 14
                }

                Connections {
                    target: clipboardDialog
                    function onKeyboardIndexChanged() {
                        if (clipboardDialog.keyboardIndex >= 0 && clipboardDialog.keyboardIndex < clipboardList.count)
                            clipboardList.positionViewAtIndex(clipboardDialog.keyboardIndex, ListView.Contain);
                    }
                }
            }

            // Bottom Thin Divider
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: ClipboardStyle.separator
            }

            // Footer Link Row
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    StyledText {
                        text: "Clear history"
                        color: clearMouse.containsMouse ? ClipboardStyle.accent : ClipboardStyle.dim
                        font.pixelSize: 12

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Cliphist.wipe()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: "Shift+Del delete  ·  Ctrl+Enter path"
                        color: ClipboardStyle.muted
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    Rectangle {
        id: previewCard
        visible: clipboardDialog.previewRequested && clipboardDialog.previewEntry !== ""
        x: clipboardDialog.embedded
            ? 0
            : clipboardDialog.clamp(
                clipboardDialog.previewOnLeft ? menuCard.x - width - 10 : menuCard.x + menuCard.width + 10,
                clipboardDialog.edgeMargin,
                Math.max(clipboardDialog.edgeMargin, clipboardDialog.width - width - clipboardDialog.edgeMargin))
        y: clipboardDialog.embedded
            ? 0
            : clipboardDialog.clamp(menuCard.y, clipboardDialog.edgeMargin, Math.max(clipboardDialog.edgeMargin, clipboardDialog.height - height - clipboardDialog.edgeMargin))
        width: clipboardDialog.previewWidth
        height: Math.min(300, Math.max(150, menuCard.height))
        color: ClipboardStyle.panel
        border.color: ClipboardStyle.line
        border.width: 1
        radius: ClipboardStyle.radius
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            StyledText {
                text: clipboardDialog.previewIsImage ? "Image preview" : "Clipboard details"
                color: ClipboardStyle.dim
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: ClipboardStyle.separator }

            CliphistImage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: clipboardDialog.previewIsImage
                entry: visible ? clipboardDialog.previewEntry : ""
                active: visible
                maxWidth: previewCard.width - 24
                maxHeight: previewCard.height - 56
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !clipboardDialog.previewIsImage
                clip: true
                contentWidth: width
                contentHeight: previewText.paintedHeight
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: previewText
                    width: parent.width
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: clipboardDialog.previewText
                    textFormat: TextEdit.PlainText
                    color: ClipboardStyle.fg
                    selectionColor: ClipboardStyle.accent
                    selectedTextColor: ClipboardStyle.bg
                    font.family: ClipboardStyle.fontFamily
                    font.pixelSize: 14
                }
            }
        }
    }
}
