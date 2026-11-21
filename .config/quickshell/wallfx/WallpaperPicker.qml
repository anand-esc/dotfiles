// WallpaperPicker.qml — coverflow of skewed (parallelogram) cards.
// Adapted from pocket-dots by diegoMalagrida (https://github.com/diegoMalagrida/pocket-dots), GPL-3.0.
// This file is licensed GPL-3.0; see LICENSE in this folder.
//
// Super+Shift+W toggles it. ←/→ or scroll to browse, Enter or click the centre card to apply,
// Esc or click outside to close. Cards read small thumbnails (scripts/wall-thumbs.sh) instead of
// the full wallpapers, so browsing stays smooth.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import Qt.labs.folderlistmodel

Scope {
    id: root
    property bool open: false
    readonly property string home: Quickshell.env("HOME")
    readonly property string wallsDir: home + "/Pictures/Wallpapers"
    readonly property string thumbsDir: home + "/.cache/wallfx/thumbs"

    // "1044380.jpg.jpg" -> "~/Pictures/Wallpapers/1044380.jpg"
    function originalOf(thumbName) { return root.wallsDir + "/" + String(thumbName).replace(/\.jpg$/, "") }
    function apply(thumbName) {
        Quickshell.execDetached([root.home + "/.local/bin/wallset", root.originalOf(thumbName)])
        root.open = false
    }

    Process {
        id: thumbsProc
        command: ["bash", Qt.resolvedUrl("scripts/wall-thumbs.sh").toString().replace("file://", ""), root.wallsDir, root.thumbsDir]
        onExited: if (wallModel.count === 0) { wallModel.folder = ""; wallModel.folder = "file://" + root.thumbsDir }
    }
    function refreshThumbs() { thumbsProc.running = false; thumbsProc.running = true }

    // While you browse, cut out characters of wallpapers that haven't been prepared yet.
    Process { id: warmProc; command: ["nice", "-n", "15", root.home + "/.local/bin/wallfx", "warm"] }
    function warmTransitions() { if (!warmProc.running) warmProc.running = true }
    Component.onCompleted: root.refreshThumbs()

    GlobalShortcut { appid: "wallfx"; name: "picker"; description: "Wallpaper picker"; onPressed: root.open = !root.open }
    IpcHandler { target: "picker"; function toggle(): string { root.open = !root.open; return root.open ? "open" : "closed" } }
    HyprlandFocusGrab { windows: [win]; active: root.open; onCleared: root.open = false }

    // Which transition each wallpaper gets (wallfx writes it), and which one is on now.
    property var kinds: ({})
    property string currentName: ""
    FileView {
        path: root.home + "/.cache/wallfx/kinds.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.kinds = JSON.parse(text()) } catch (e) {} }
    }
    FileView {
        path: root.home + "/.local/state/caelestia/wallpaper/path.txt"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: root.currentName = text().trim().split("/").pop()
    }
    function centreOnCurrent() {
        for (let i = 0; i < wallModel.count; i++) {
            if (String(wallModel.get(i, "fileName")) === root.currentName + ".jpg") {
                carousel.currentIndex = i
                carousel.positionViewAtIndex(i, ListView.Center)
                return
            }
        }
    }

    FolderListModel {
        id: wallModel
        folder: "file://" + root.thumbsDir
        nameFilters: ["*.jpg"]
        showDirs: false
        sortField: FolderListModel.Name
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.open || stage.opacity > 0
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "wallfx-picker"

        Item {
            id: stage
            anchors.fill: parent
            focus: true
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.open ? 210 : 110; easing.type: root.open ? Easing.OutCubic : Easing.InCubic } }

            Connections {
                target: root
                function onOpenChanged() {
                    if (!root.open) return
                    stage.forceActiveFocus()
                    root.centreOnCurrent()
                    root.refreshThumbs()
                    root.warmTransitions()
                }
            }

            Keys.onEscapePressed: root.open = false
            Keys.onLeftPressed: carousel.decrementCurrentIndex()
            Keys.onRightPressed: carousel.incrementCurrentIndex()
            Keys.onReturnPressed: carousel.applyCurrent()
            Keys.onEnterPressed: carousel.applyCurrent()
            WheelHandler {
                onWheel: (e) => {
                    if (e.angleDelta.y > 0 || e.angleDelta.x > 0) carousel.decrementCurrentIndex()
                    else carousel.incrementCurrentIndex()
                }
            }

            // A light veil so the cards read over anything; click it to close.
            Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.35 }
            MouseArea { anchors.fill: parent; z: -1; onClicked: root.open = false }

            ListView {
                id: carousel
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 560
                orientation: ListView.Horizontal
                model: wallModel
                property real iw: 720
                property real ih: 406
                property real skew: -0.35
                property real bw: 3
                property real slotW: 360
                property real sideBase: 0.56
                readonly property real imgW: iw + ih * Math.abs(skew) + 12
                spacing: 0; clip: false; cacheBuffer: 2500
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - slotW) / 2
                preferredHighlightEnd: (width + slotW) / 2
                highlightMoveDuration: 420
                highlightMoveVelocity: 3000
                snapMode: ListView.SnapToItem
                boundsBehavior: Flickable.StopAtBounds
                maximumFlickVelocity: 6000

                function applyCurrent() {
                    if (currentIndex < 0 || wallModel.count <= currentIndex) return
                    root.apply(wallModel.get(currentIndex, "fileName"))
                }

                delegate: Item {
                    id: slot
                    required property int index
                    required property string fileName
                    required property url fileUrl
                    readonly property string original: String(fileName).replace(/\.jpg$/, "")
                    readonly property bool isCurrent: original === root.currentName
                    readonly property string kind: root.kinds[original] ?? "pending"
                    width: carousel.slotW
                    height: carousel.height
                    readonly property real d: (x + width / 2 - (carousel.contentX + carousel.width / 2)) / carousel.slotW
                    readonly property real ad: Math.abs(d)
                    readonly property real sc: ad <= 1
                        ? carousel.sideBase + (1 - carousel.sideBase) * Math.pow(1 - ad, 1.35)
                        : carousel.sideBase * Math.pow(0.86, ad - 1)
                    z: Math.round(100 - ad * 10)
                    opacity: Math.max(0, Math.min(1, 1.15 - 0.34 * ad))

                    Item {
                        id: card
                        anchors.centerIn: parent
                        width: carousel.iw
                        height: carousel.ih
                        scale: slot.sc
                        transformOrigin: Item.Center
                        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, carousel.skew, 0, -carousel.skew * carousel.ih / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }

                        Rectangle {
                            anchors.fill: parent
                            color: "#101010"
                            border.width: slot.isCurrent ? 3 : 1
                            border.color: slot.isCurrent ? "#ffffff" : Qt.rgba(1, 1, 1, slot.ad < 0.5 ? 0.55 : 0.15)
                        }
                        Item {
                            anchors.fill: parent; anchors.margins: carousel.bw; clip: true
                            Image {
                                anchors.centerIn: parent
                                width: carousel.imgW
                                height: carousel.ih
                                fillMode: Image.PreserveAspectCrop
                                source: slot.fileUrl
                                asynchronous: true; cache: true; mipmap: true
                                sourceSize: Qt.size(carousel.imgW, carousel.ih)
                                transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -carousel.skew, 0, carousel.skew * carousel.ih / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: slot.ad < 0.5 ? carousel.applyCurrent() : (carousel.currentIndex = slot.index)
                        }

                        // Badges: which effect this wallpaper gets, and the one that is on now.
                        Row {
                            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 26; bottomMargin: 18 }
                            spacing: 8
                            Badge {
                                text: slot.kind === "outline" ? "✎ outline" : slot.kind === "colonies" ? "▦ colonies" : "… preparing"
                            }
                            Badge { visible: slot.isCurrent; text: "● current"; strong: true }
                        }
                    }
                }
            }

            // ←/→ hint under the carousel
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: carousel.bottom; topMargin: -40 }
                text: "← →  browse     ⏎  apply     esc  close"
                color: "white"; opacity: 0.6; font.pixelSize: 15
            }

            Text {
                anchors.centerIn: parent
                visible: wallModel.count === 0
                text: "No wallpapers in ~/Pictures/Wallpapers"
                color: "white"
                font.pixelSize: 22
                opacity: 0.85
            }
        }
    }

    component Badge: Rectangle {
        property alias text: label.text
        property bool strong: false
        radius: height / 2
        height: label.implicitHeight + 10
        width: label.implicitWidth + 22
        color: strong ? "#ffffff" : Qt.rgba(0, 0, 0, 0.62)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
        Text {
            id: label
            anchors.centerIn: parent
            color: parent.strong ? "#000000" : "#ffffff"
            font.pixelSize: 17; font.weight: Font.DemiBold
        }
    }
}
