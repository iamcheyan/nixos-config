import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "iamcheyan.active-window"

    property int titleAreaWidth: Number(setting("maxWidth", 320))

    // Read immutable JSON snapshots from Hyprland instead of traversing
    // Quickshell's live Wayland toplevel/screen models. The latter can mutate
    // while an application surface is being created or destroyed.
    property var hyprClients: []
    property var hyprMonitors: []
    readonly property var barWindow: root.QsWindow ? root.QsWindow.window : null
    readonly property string barScreenName: root.barWindow && root.barWindow.screen
        ? String(root.barWindow.screen.name || "") : ""
    readonly property int barMonitorId: {
        const name = root.barScreenName;
        const monitors = root.hyprMonitors || [];
        for (let i = 0; i < monitors.length; i++) {
            if (String(monitors[i]?.name || "") === name)
                return Number(monitors[i]?.id ?? -1);
        }
        return -1;
    }
    readonly property var focusedClient: {
        const clients = root.hyprClients || [];
        const monitorId = root.barMonitorId;
        const active = clients.find(client =>
            client && client.mapped && !client.hidden &&
            Number(client.focusHistoryID) === 0 &&
            (monitorId < 0 || Number(client.monitor) === monitorId));
        if (active) return active;
        if (monitorId < 0)
            return clients.find(client => client && client.mapped && !client.hidden) || null;
        return null;
    }

    readonly property bool hasWindow: root.focusedClient !== null &&
        Boolean((root.windowTitle && root.windowTitle.length > 0) ||
                (root.windowAppId && root.windowAppId.length > 0))

    readonly property string windowTitle: root.focusedClient?.title ?? ""
    readonly property string windowAppId: root.focusedClient
        ? String(root.focusedClient.class || root.focusedClient.initialClass || "") : ""

    Process {
        id: clientsProcess
        command: ["/run/current-system/sw/bin/hyprctl", "clients", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse((text || "[]").trim());
                    root.hyprClients = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.hyprClients = [];
                }
            }
        }
    }

    Process {
        id: monitorsProcess
        command: ["/run/current-system/sw/bin/hyprctl", "monitors", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse((text || "[]").trim());
                    root.hyprMonitors = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.hyprMonitors = [];
                }
            }
        }
    }

    Timer {
        id: clientsPoll
        interval: 350
        running: true
        repeat: true
        onTriggered: if (!clientsProcess.running) clientsProcess.running = true
    }

    Timer {
        id: monitorsPoll
        interval: 1000
        running: true
        repeat: true
        onTriggered: if (!monitorsProcess.running) monitorsProcess.running = true
    }

    readonly property string displayTitle: root.hasWindow
        ? (root.windowTitle || root.windowAppId)
        : root.desktopDisplayName

    readonly property string displayIcon: root.hasWindow
        ? root.resolveAppIcon(root.windowAppId)
        : root.osIconPath

    // --- Distro & System Release Detection ---
    property string distroName: "Linux"
    property string distroId: "nixos"
    property string distroVersion: ""
    property string distroLike: ""

    // Nixarchy release detection (when running under Nixarchy on NixOS)
    readonly property string nixFlakePath: {
        const envFlake = Quickshell.env("NIXARCHY_FLAKE");
        if (envFlake && envFlake.length > 0) return envFlake;
        const home = Quickshell.env("HOME");
        if (home && home.length > 0) return home + "/nixos-config";
        return "/home/tetsuya/nixos-config";
    }

    property string nixarchyRelease: ""

    FileView {
        id: osReleaseFile
        path: "/etc/os-release"
        printErrors: false
        onLoaded: root.parseOsRelease(text())
    }

    FileView {
        id: flakeLockFile
        path: root.nixFlakePath + "/flake.lock"
        printErrors: false
        watchChanges: true
        onLoaded: root.parseFlakeLock(text())
        onFileChanged: reload()
    }

    FileView {
        id: flakeNixFile
        path: root.nixFlakePath + "/flake.nix"
        printErrors: false
        watchChanges: true
        onLoaded: root.parseFlakeNix(text())
        onFileChanged: reload()
    }

    Component.onCompleted: {
        clientsProcess.running = true;
        monitorsProcess.running = true;

        if (osReleaseFile.text()) {
            root.parseOsRelease(osReleaseFile.text());
        }
        if (flakeLockFile.text()) {
            root.parseFlakeLock(flakeLockFile.text());
        }
        if (root.nixarchyRelease === "" && flakeNixFile.text()) {
            root.parseFlakeNix(flakeNixFile.text());
        }
    }

    function parseOsRelease(text) {
        if (!text) return;
        const prettyMatch = text.match(/^PRETTY_NAME="?(.+?)"?$/m);
        const nameMatch = text.match(/^NAME="?(.+?)"?$/m);
        root.distroName = prettyMatch ? prettyMatch[1] : (nameMatch ? nameMatch[1].replace(/Linux/i, "").trim() : "Linux");

        const verMatch = text.match(/^VERSION_ID="?(.+?)"?$/m);
        root.distroVersion = verMatch ? verMatch[1] : "";

        const idMatch = text.match(/^ID="?(.+?)"?$/m);
        root.distroId = idMatch ? idMatch[1] : "";

        const likeMatch = text.match(/^ID_LIKE="?(.+?)"?$/m);
        root.distroLike = likeMatch ? likeMatch[1] : "";
    }

    function parseFlakeLock(rawText) {
        if (!rawText) return;
        try {
            const data = JSON.parse(rawText);
            const ref = data?.nodes?.nixarchy?.original?.ref;
            if (ref && typeof ref === "string" && ref.length > 0) {
                root.nixarchyRelease = ref;
                return;
            }
        } catch (e) {}

        const match = String(rawText).match(/"nixarchy"[\s\S]*?"ref":\s*"(v[0-9a-zA-Z._-]+)"/);
        if (match && match[1]) {
            root.nixarchyRelease = match[1];
        }
    }

    function parseFlakeNix(rawText) {
        if (!rawText || root.nixarchyRelease !== "") return;
        const match = String(rawText).match(/github:olafkfreund\/nixarchy\/(v[0-9a-zA-Z._-]+)/);
        if (match && match[1]) {
            root.nixarchyRelease = match[1];
        }
    }

    readonly property string desktopDisplayName: {
        var name = root.distroName;
        if (!name || name.length === 0) return "Desktop";
        name = name.replace(/\s*\([^)]*\)\s*$/, "").trim();
        var ver = root.distroVersion;
        if (ver && ver.length > 0 && !name.includes(ver)) {
            name += " " + ver;
        }
        if (root.nixarchyRelease && root.nixarchyRelease.length > 0) {
            name += " | Nixarchy " + root.nixarchyRelease;
        }
        return name || "Desktop";
    }

    function osIconName() {
        const id = (root.distroId || "").toLowerCase();
        const like = (root.distroLike || "").toLowerCase();
        const name = (root.distroName || "").toLowerCase();

        const idMap = {
            "fedora": "fedora",
            "arch": "arch",
            "artix": "arch",
            "cachyos": "arch",
            "ubuntu": "ubuntu",
            "debian": "debian",
            "raspbian": "debian",
            "kali": "debian",
            "linuxmint": "mint",
            "endeavouros": "endeavouros",
            "nixos": "nixos",
            "manjaro": "manjaro",
            "opensuse": "opensuse",
            "suse": "opensuse",
            "popos": "pop-os",
            "zorin": "zorin-os",
            "centos": "centos",
            "redhat": "redhat",
            "rocky": "rockylinux",
            "alpine": "alpine",
            "gentoo": "gentoo",
            "funtoo": "gentoo",
        };
        if (id in idMap) return idMap[id];

        const likeMap = {
            "fedora": "fedora",
            "arch": "arch",
            "debian": "debian",
            "ubuntu": "ubuntu",
            "rhel": "redhat",
            "centos": "centos",
            "alpine": "alpine",
            "gentoo": "gentoo",
        };
        const likes = like.split(/\s+/);
        for (let i = 0; i < likes.length; i++) {
            if (likes[i] in likeMap) return likeMap[likes[i]];
        }

        if (name.includes("endeavouros")) return "endeavouros";
        if (name.includes("nixos")) return "nixos";
        if (name.includes("opensuse")) return "opensuse";
        if (name.includes("manjaro")) return "manjaro";
        if (name.includes("zorin")) return "zorin-os";
        if (name.includes("rocky linux")) return "rockylinux";
        if (name.includes("centos")) return "centos";
        if (name.includes("red hat")) return "redhat";
        if (name.includes("alpine")) return "alpine";
        if (name.includes("gentoo")) return "gentoo";
        if (name.includes("mint")) return "mint";
        if (name.includes("pop")) return "pop-os";
        if (name.includes("ubuntu")) return "ubuntu";
        if (name.includes("debian")) return "debian";
        if (name.includes("arch")) return "arch";
        if (name.includes("fedora")) return "fedora";

        return "fedora";
    }

    readonly property string osIconPath: Qt.resolvedUrl("icons/" + root.osIconName() + ".svg")

    function resolveAppIcon(appId) {
        if (!appId || appId.length === 0) return "";

        // A Wayland appId is not necessarily the icon name. Resolve the
        // desktop entry first so apps such as Firefox and Alacritty keep their
        // icons even when their startup class and desktop file ID differ.
        var names = [];
        var addName = function(value) {
            if (value && String(value).length > 0 && names.indexOf(String(value)) < 0) {
                names.push(String(value));
            }
        };

        var entry = DesktopEntries.heuristicLookup(appId);
        if (!entry) entry = DesktopEntries.byId(appId);
        if (entry) addName(entry.icon);

        var appIdLower = String(appId).toLowerCase();
        var applications = DesktopEntries.applications.values || [];
        for (var i = 0; i < applications.length; i++) {
            var candidate = applications[i];
            var startupClass = String(candidate.startupClass || "").toLowerCase();
            var entryId = String(candidate.id || "").replace(/\.desktop$/i, "").toLowerCase();
            if (startupClass === appIdLower || entryId === appIdLower) {
                addName(candidate.icon);
                break;
            }
        }

        addName(appId);
        addName(appIdLower);
        var parts = String(appId).split(".");
        addName(parts[parts.length - 1].toLowerCase());

        for (var j = 0; j < names.length; j++) {
            var icon = names[j];
            if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon;
            if (icon.charAt(0) === "/") return Util.fileUrl(icon);

            // Reuse Omarchy's live icon index. It finds icons installed in
            // XDG data directories even when Qt's theme cache does not.
            var appLibrary = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null;
            if (appLibrary && typeof appLibrary.iconSource === "function") {
                var indexed = appLibrary.iconSource(icon);
                if (indexed) return indexed;
            }

            var resolved = Quickshell.iconPath(icon, true);
            if (resolved) return resolved;
        }
        return "";
    }

    function fallbackLetter(appId, title) {
        const source = (appId && appId.length > 0) ? appId : (title ?? "");
        if (!source || source.length === 0) return "?";
        return source.charAt(0).toUpperCase();
    }

    visible: !root.vertical
    implicitHeight: root.barSize
    implicitWidth: Math.min(root.titleAreaWidth, Style.space(8) * 2 + 16 + Style.space(6) + titleText.implicitWidth)

    Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Row {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(6)

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14

            Image {
                id: iconImage
                anchors.fill: parent
                source: root.displayIcon
                sourceSize.width: 14 * Screen.devicePixelRatio
                sourceSize.height: 14 * Screen.devicePixelRatio
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
                smooth: true
            }

            Rectangle {
                anchors.fill: parent
                visible: !iconImage.visible
                radius: 3
                color: Util.alpha(root.bar ? root.bar.barForeground : Color.foreground, 0.15)

                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.fallbackLetter(root.windowAppId, root.displayTitle)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: 9
                    font.bold: true
                    color: root.bar ? root.bar.barForeground : Color.foreground
                }
            }
        }

        Text {
            id: titleText
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(root.titleAreaWidth - Style.space(8) * 2 - 14 - Style.space(6), implicitWidth)
            text: root.displayTitle
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            opacity: root.hasWindow ? 0.95 : 0.80
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.ArrowCursor

        onEntered: {
            if (root.bar) root.bar.showTooltip(root, root.displayTitle);
        }
        onExited: {
            if (root.bar) root.bar.hideTooltip(root);
        }
    }
}
