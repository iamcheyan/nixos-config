import QtQuick 2.15
import QtQuick.Controls 2.15 as Controls
import QtQuick.Effects
import QtQuick.Layouts 1.15
import SddmComponents 2.0

FocusScope {
    id: root

    property string wallpaperPath: config.stringValue("background")
    property string username: userSource.currentItem
        ? userSource.currentItem.userName : userModel.lastUser
    property bool passwordVisible: false
    property string failureMessage: ""
    property bool authenticating: false

    focus: true

    // SDDM exposes the last user inconsistently between the greeter and
    // --test-mode. Keep a tiny transparent model view alive so model.name is
    // available exactly as it was in the original user delegate.
    ListView {
        id: userSource
        opacity: 0
        width: 1
        height: 1
        model: userModel
        currentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
        interactive: false
        delegate: Item {
            width: 1
            height: 1
            property string userName: model.name || ""
        }
    }

    function showPasswordInput() {
        root.passwordVisible = true
        passwordField.forceActiveFocus()
    }

    function handlePasswordShortcut(event) {
        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
            return

        sessionBox.popup.close()
        powerBox.popup.close()
        root.showPasswordInput()
        event.accepted = true
    }

    function login() {
        if (root.authenticating || root.username.length === 0 || passwordField.text.length === 0)
            return

        root.authenticating = true
        root.failureMessage = ""
        sddm.login(root.username, passwordField.text, sessionBox.currentIndex)
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.authenticating = false
            root.failureMessage = "Authentication failed"
            passwordField.selectAll()
            passwordField.forceActiveFocus()
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            clock.text = Qt.formatDateTime(new Date(), "HH:mm")
            date.text = Qt.formatDateTime(new Date(), "dddd, MMMM d")
        }
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: root.handlePasswordShortcut(event)

    Image {
        id: wallpaper
        anchors.fill: parent
        source: root.wallpaperPath.length > 0
            ? (root.wallpaperPath.startsWith("file://")
                ? root.wallpaperPath
                : "file://" + root.wallpaperPath)
            : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        visible: status === Image.Ready
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: -0.05
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: wallpaper.status === Image.Ready ? 0.30 : 1.0
    }

    Column {
        anchors.top: parent.top
        anchors.topMargin: Math.max(48, parent.height * 0.07)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#a0ffffff"
            font.pixelSize: 15
        }

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#f5ffffff"
            font.pixelSize: Math.min(96, Math.max(68, root.height * 0.11))
            font.weight: Font.Light
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.max(8, parent.height * 0.02)
        width: Math.min(320, parent.width - 64)
        spacing: 10

        Item {
            id: avatarFrame
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76
            height: 76

            property int avatarIndex: 0
            property bool avatarLoaded: false

            function fileUrl(path) {
                if (!path || path.length === 0)
                    return ""
                return path.startsWith("file://") ? path : "file://" + path
            }

            property var avatarCandidates: [
                "file:///var/lib/AccountsService/icons/" + root.username,
                Qt.resolvedUrl("assets/" + root.username + ".jpg"),
                fileUrl("/home/" + root.username + "/.face"),
                fileUrl("/home/" + root.username + "/.face.icon"),
                // Local fallback keeps the preview usable when SDDM has no
                // AccountsService icon and does not expose lastUser yet.
                Qt.resolvedUrl("assets/tetsuya.jpg")
            ]

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#1affffff"
                border.width: 1
                border.color: "#38ffffff"
            }

            Item {
                id: avatarLayer
                anchors.fill: parent
                anchors.margins: 1
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: avatarMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.02
                }

                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: avatarFrame.avatarIndex < avatarFrame.avatarCandidates.length
                        ? avatarFrame.avatarCandidates[avatarFrame.avatarIndex] : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    visible: avatarFrame.avatarLoaded
                    onStatusChanged: {
                        if (status === Image.Ready) {
                            avatarFrame.avatarLoaded = true
                        } else if (status === Image.Error || status === Image.Null) {
                            avatarFrame.avatarLoaded = false
                            if (avatarFrame.avatarIndex + 1 < avatarFrame.avatarCandidates.length)
                                avatarFrame.avatarIndex += 1
                        }
                    }
                    onSourceChanged: avatarFrame.avatarLoaded = false
                }

                Item {
                    id: avatarMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "white"
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: "󰀄"
                color: "#e0ffffff"
                font.pixelSize: 34
                font.family: "JetBrainsMono Nerd Font"
                visible: !avatarFrame.avatarLoaded
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.showPasswordInput()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.username
            color: "#e0ffffff"
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.passwordVisible && root.failureMessage.length === 0
            text: "Click or press Space"
            color: "#80ffffff"
            font.pixelSize: 13
        }

        Rectangle {
            id: passwordCard
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(236, parent.width)
            height: 34
            visible: root.passwordVisible
            radius: height / 2
            color: "#70000000"
            border.width: 1
            border.color: root.failureMessage.length > 0 ? "#b8ff7770" : "#38ffffff"

            TextInput {
                id: passwordField
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: submitLabel.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                color: "#f5ffffff"
                font.pixelSize: 13
                echoMode: TextInput.Password
                passwordCharacter: "•"
                enabled: !root.authenticating
                focus: root.passwordVisible
                onAccepted: root.login()
            }

            Text {
                id: submitLabel
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.authenticating ? "…" : "󰜴"
                color: "#eaffffff"
                font.pixelSize: 19
                font.family: "JetBrainsMono Nerd Font"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    enabled: !root.authenticating
                    onClicked: root.login()
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: passwordField.text.length === 0 && root.failureMessage.length === 0
                text: "Enter Password"
                color: "#70ffffff"
                font.pixelSize: 13
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.failureMessage.length > 0
            text: root.failureMessage
            color: "#e8aaa0"
            font.pixelSize: 12
        }

    }

    // Keep session selection on the left, matching the lock-screen layout.
    Controls.ComboBox {
        id: sessionBox
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.max(28, parent.width * 0.03)
        anchors.bottomMargin: Math.max(22, parent.height * 0.04)
        width: 160
        height: 34
        model: sessionModel
        currentIndex: sessionModel.lastIndex
        textRole: "name"
        font.pixelSize: 12
        delegate: Controls.ItemDelegate {
            width: sessionBox.width - 8
            height: 34
            highlighted: sessionBox.highlightedIndex === index
            contentItem: Text {
                text: model.name
                color: highlighted ? "#f5ffffff" : "#d8ffffff"
                font.family: sessionBox.font.family
                font.pixelSize: sessionBox.font.pixelSize
                font.weight: Font.Normal
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 10
                color: highlighted ? "#28ffffff" : "transparent"
            }
        }
        popup: Controls.Popup {
            y: -height - 8
            width: sessionBox.width
            padding: 4
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: sessionBox.popup.visible ? sessionBox.delegateModel : null
                currentIndex: sessionBox.highlightedIndex
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                Keys.onPressed: root.handlePasswordShortcut(event)
            }

            background: Rectangle {
                radius: 14
                color: "#b010151b"
                border.width: 1
                border.color: "#38ffffff"
            }
        }
        contentItem: Text {
            text: "Desktop  ·  " + sessionBox.displayText
            color: "#cfffffff"
            font: sessionBox.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: height / 2
            color: "#38000000"
            border.width: 1
            border.color: "#18ffffff"
        }
        indicator: Text {
            x: sessionBox.width - width - 12
            y: (sessionBox.height - height) / 2
            text: "⌄"
            color: "#a8ffffff"
            font.pixelSize: 14
            font.family: "JetBrainsMono Nerd Font"
        }
        Keys.onPressed: root.handlePasswordShortcut(event)
    }

    Controls.ComboBox {
        id: powerBox
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Math.max(28, parent.width * 0.03)
        anchors.bottomMargin: Math.max(22, parent.height * 0.04)
        width: 36
        height: 34
        model: ["Sleep", "Restart", "Power off"]
        font.pixelSize: 12
        onActivated: {
            if (index === 0) sddm.suspend()
            else if (index === 1) sddm.reboot()
            else if (index === 2) sddm.powerOff()
        }
        delegate: Controls.ItemDelegate {
            width: powerBox.popup.width - 8
            height: 34
            highlighted: powerBox.highlightedIndex === index
            contentItem: Text {
                text: modelData
                color: highlighted ? "#f5ffffff" : "#d8ffffff"
                font.family: powerBox.font.family
                font.pixelSize: powerBox.font.pixelSize
                font.weight: Font.Normal
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 10
                color: highlighted ? "#28ffffff" : "transparent"
            }
        }
        popup: Controls.Popup {
            x: powerBox.width - width
            y: -height - 8
            width: 150
            padding: 4
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: powerBox.popup.visible ? powerBox.delegateModel : null
                currentIndex: powerBox.highlightedIndex
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                Keys.onPressed: root.handlePasswordShortcut(event)
            }

            background: Rectangle {
                radius: 14
                color: "#b010151b"
                border.width: 1
                border.color: "#38ffffff"
            }
        }
        contentItem: Text {
            text: "󰐥"
            color: "#e0ffffff"
            font.family: powerBox.font.family
            font.pixelSize: 17
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: height / 2
            color: "#38000000"
            border.width: 1
            border.color: "#18ffffff"
        }
        indicator: Text {
            visible: false
            x: powerBox.width - width - 12
            y: (powerBox.height - height) / 2
            text: "⌄"
            color: "#a8ffffff"
            font.pixelSize: 14
            font.family: "JetBrainsMono Nerd Font"
        }
        Keys.onPressed: root.handlePasswordShortcut(event)
    }
}
