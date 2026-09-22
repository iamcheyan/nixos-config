pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons

FocusScope {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: false
  property bool loadBackground: false
  property string passwordText: ""
  property bool passwordVisible: false

  readonly property var avatarCandidates: [
    "file:///var/lib/AccountsService/icons/" + (Quickshell.env("USER") || ""),
    "file://" + (Quickshell.env("HOME") || "") + "/.face",
    "file://" + (Quickshell.env("HOME") || "") + "/.face.icon"
  ]
  readonly property var avatarPaths: [
    "/var/lib/AccountsService/icons/" + (Quickshell.env("USER") || ""),
    (Quickshell.env("HOME") || "") + "/.face",
    (Quickshell.env("HOME") || "") + "/.face.icon"
  ]
  property int avatarIndex: 0
  property bool avatarLoaded: false
  property bool avatarCandidateAvailable: false
  readonly property string avatarSource: avatarIndex < avatarCandidates.length
    && avatarCandidateAvailable ? avatarCandidates[avatarIndex] : ""

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  property string timeText: Qt.formatDateTime(new Date(), "HH:mm")
  property string dateText: Qt.formatDateTime(new Date(), "dddd, MMMM d")

  focus: inputEnabled
  onInputEnabledChanged: if (inputEnabled) forceActiveFocus()
  onAvatarIndexChanged: {
    avatarCandidateAvailable = false
    avatarLoaded = false
    avatarProbe.reload()
  }

  FileView {
    id: avatarProbe
    path: root.avatarIndex < root.avatarPaths.length ? root.avatarPaths[root.avatarIndex] : ""
    printErrors: false
    onLoaded: root.avatarCandidateAvailable = true
    onLoadFailed: {
      root.avatarCandidateAvailable = false
      if (root.avatarIndex + 1 < root.avatarCandidates.length)
        root.avatarIndex += 1
    }
  }

  function cancelPasswordInput() {
    if (!root.passwordVisible || root.authenticatingPassword) return
    root.passwordTextEdited("")
    root.clearFailureRequested()
    root.passwordVisible = false
    root.forceActiveFocus()
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.timeText = Qt.formatDateTime(new Date(), "HH:mm")
      root.dateText = Qt.formatDateTime(new Date(), "dddd, MMMM d")
    }
  }

  Keys.onPressed: event => {
    root.wakeRequested()
    if (event.key === Qt.Key_Space && !root.passwordVisible) {
      root.passwordVisible = true
      root.forceActiveFocus()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape && root.passwordVisible) {
      root.cancelPasswordInput()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!root.passwordVisible) {
        root.passwordVisible = true
        root.forceActiveFocus()
      } else {
        root.submitPassword(root.passwordText)
      }
      event.accepted = true
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onPressed: {
      root.wakeRequested()
      root.passwordVisible = true
      root.forceActiveFocus()
    }
  }

  Image {
    id: background
    anchors.fill: parent
    source: root.loadBackground && root.backgroundPath.length > 0
      ? root.backgroundPath + "?v=" + root.backgroundVersion : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
    visible: false
  }

  Rectangle { anchors.fill: parent; color: "#101014" }

  MultiEffect {
    anchors.fill: parent
    source: background
    blurEnabled: background.status === Image.Ready
    blur: 1.0
    blurMax: 32
    saturation: -0.05
  }

  Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.30 }

  Column {
    anchors.top: parent.top
    anchors.topMargin: Math.max(48, parent.height * 0.07)
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.dateText
      color: "#a0ffffff"
      font.pixelSize: 15
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.timeText
      color: "#f5ffffff"
      font.pixelSize: Math.min(96, Math.max(68, root.height * 0.11))
      font.weight: Font.Light
    }
  }

  Column {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.max(48, parent.height * 0.07)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(320, parent.width - 64)
    spacing: 10

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 76
      height: 76

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
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: avatarMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: avatarImage
          anchors.fill: parent
          source: root.avatarSource
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
          visible: root.avatarLoaded
          onStatusChanged: {
            if (status === Image.Ready) root.avatarLoaded = true
            else if (status === Image.Error || status === Image.Null) {
              root.avatarLoaded = false
              if (root.avatarIndex + 1 < root.avatarCandidates.length)
                root.avatarIndex += 1
            }
          }
          onSourceChanged: root.avatarLoaded = false
        }

        Item {
          id: avatarMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
        }
      }

      Text {
        anchors.centerIn: parent
        text: "󰀄"
        color: "#e0ffffff"
        font.pixelSize: 34
        font.family: Style.font.family
        visible: !root.avatarLoaded
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Quickshell.env("USER") || ""
      color: "#e0ffffff"
      font.pixelSize: 16
      font.weight: Font.DemiBold
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: !root.passwordVisible
      text: "Click or press Space"
      color: "#80ffffff"
      font.pixelSize: 13
    }

    Rectangle {
      id: passwordCard
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(236, parent.width)
      height: 34
      visible: root.inputEnabled && root.passwordVisible
      radius: height / 2
      color: "#70000000"
      border.width: 1
      border.color: root.failureMessage.length > 0 ? "#b8ff7770" : "#38ffffff"

      TextInput {
        id: passwordInput
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
        text: root.passwordText
        enabled: root.inputEnabled && !root.authenticatingPassword
        focus: root.inputEnabled && root.passwordVisible
        activeFocusOnPress: false
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        onTextChanged: if (root.passwordText !== text) root.passwordTextEdited(text)
        onAccepted: root.submitPassword(text)
        Keys.onPressed: root.wakeRequested()
      }

      Text {
        id: submitLabel
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.authenticatingPassword ? "…" : "󰜴"
        color: "#eaffffff"
        font.pixelSize: 19
        font.family: Style.font.family
        MouseArea {
          anchors.fill: parent
          anchors.margins: -8
          enabled: root.inputEnabled && !root.authenticatingPassword
          onClicked: root.submitPassword(root.passwordText)
        }
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        visible: passwordInput.text.length === 0 && root.failureMessage.length === 0
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
}
