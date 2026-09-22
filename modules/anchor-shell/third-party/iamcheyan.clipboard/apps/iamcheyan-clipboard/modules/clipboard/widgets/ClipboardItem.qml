pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../services"

Rectangle {
    id: root

    required property string entry
    property int itemIndex: 0
    property bool selected: false
    signal itemClicked()
    signal hoveredChanged(bool hovered)
    signal pasteAsPathRequested(string entry)
    signal mouseMoved()

    readonly property bool isImage: Cliphist.entryIsImage(entry)
    // File paths: "file:///..." URIs or absolute POSIX paths ("/...").
    // The raw entry has a leading id prefix ("5220\t..."); strip it first.
    readonly property bool isFilePath: /^\s*file:\/\//.test(root.cleanText) || /^\s*\//.test(root.cleanText)
    readonly property string cleanText: ClipboardStyle.cleanCliphistEntry(entry)

    // Give ListView a concrete size while its ScriptModel is being replaced.
    height: 34
    implicitHeight: height
    color: "transparent"

    Rectangle {
        anchors {
            fill: parent
            leftMargin: 6
            rightMargin: 6
            topMargin: 2
            bottomMargin: 2
        }
        radius: 6
        color: root.selected ? ClipboardStyle.surfaceSelected : mouseArea.containsMouse ? ClipboardStyle.surfaceHover : "transparent"
        visible: root.selected || mouseArea.containsMouse
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.hoveredChanged(containsMouse)
        onPositionChanged: root.mouseMoved()
        onClicked: mouse => {
            // Shift+click an image entry to paste it as a file path — same as
            // the ⇲ button / Ctrl+Enter. Text targets that can't accept an
            // image paste then receive the path string instead.
            if (root.isImage && (mouse.modifiers & Qt.ShiftModifier)) {
                mouse.accepted = true;
                root.pasteAsPathRequested(root.entry);
            } else {
                Cliphist.pasteSmart(root.entry);
                root.itemClicked();
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 8

        StyledText {
            visible: root.isImage
            Layout.preferredWidth: 18
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: "image"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 15
            color: ClipboardStyle.dim
        }

        StyledText {
            visible: root.isFilePath
            Layout.preferredWidth: 18
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: "description"
            font.family: "Material Symbols Rounded"
            font.pixelSize: 15
            color: ClipboardStyle.dim
        }

        StyledText {
            Layout.fillWidth: true
            text: root.isImage ? "Image" : root.cleanText.replace(/[\r\n]+/g, " ")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            color: ClipboardStyle.fg
            font.family: ClipboardStyle.fontFamily
            font.pixelSize: 14
        }

        Rectangle {
            visible: root.isImage && (root.selected || mouseArea.containsMouse)
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            color: pathMouse.containsMouse ? ClipboardStyle.accentSoft : "transparent"
            radius: 4

            StyledText {
                anchors.centerIn: parent
                text: "⇲"
                font.family: ClipboardStyle.fontFamily
                font.pixelSize: 16
                color: pathMouse.containsMouse ? ClipboardStyle.accent : ClipboardStyle.dim
            }

            MouseArea {
                id: pathMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    mouse.accepted = true;
                    root.pasteAsPathRequested(root.entry);
                }
            }
        }
    }
}
