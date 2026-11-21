// WallpaperFx.qml — wallpaper transitions drawn over Caelestia's background.
// Adapted from pocket-dots by diegoMalagrida (https://github.com/diegoMalagrida/pocket-dots), GPL-3.0.
// This file is licensed GPL-3.0; see LICENSE in this folder.
//
//   contagio  colonies land at random and eat through the old wallpaper in crisp 4 px cells
//   perfil    the new wallpaper has a character: a thin line draws its outline, it fills in,
//             and the rest of the world grows out of it
//
// Hand-over: this layer sits above Caelestia's wallpaper (layer Bottom, below windows) only for
// the length of a change.
//   1. load both images and the maps (async)
//   2. start the transition and fade in over the desktop (at t=0 it IS the old wallpaper)
//   3. once covered, `caelestia wallpaper -f NEW` underneath (Caelestia also re-themes)
//   4. the transition ends on the new image, which Caelestia now shows too
//   5. fade out
// If anything fails, Caelestia changes the wallpaper on its own.
//
// IPC: qs -c wallfx ipc call wallfx play OLD NEW contagio|perfil MAP LINE EMBER INK
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property int msContagio: 1800
    property int msPerfil: 2000
    property int msFade: 130
    property int msSettle: 1200       // Caelestia loads + cross-fades its new wallpaper
    property real glow: 0.9
    property real lineW: 1.5

    property string oldPath: ""
    property string newPath: ""
    property string kind: "contagio"
    property string fieldPath: ""
    property string linePath: ""
    property string phase: "idle"     // idle -> loading -> run (-> held) -> fadeout -> idle
    property real t: 0
    property real fade: 0
    property bool swapped: false
    property int gen: 0
    property int swapGen: -1
    property color ember: "orange"
    property color ink: "white"
    property real seed: 0
    property int readyCount: 0
    readonly property int screenCount: screens.instances.length
    readonly property bool active: phase !== "idle"

    function caelestiaSet(path) {
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path])
    }

    function prepare(o, n, k, f, l, em, ik) {
        if (root.active) root.finish()
        root.oldPath = o; root.newPath = n
        root.kind = k === "perfil" ? "perfil" : "contagio"
        root.fieldPath = f; root.linePath = l || f
        root.ember = em || "orange"; root.ink = ik || "white"
        root.t = 0; root.fade = 0; root.readyCount = 0; root.swapped = false
        root.gen++
        root.phase = "loading"
        watchdog.restart()
    }
    function screenReady() {
        if (root.phase !== "loading") return
        root.readyCount++
        if (root.readyCount < root.screenCount) return
        watchdog.stop()
        root.seed = Math.random() * 100
        root.phase = "run"
        run.duration = root.kind === "perfil" ? root.msPerfil : root.msContagio
        run.restart()
        fadeIn.restart()
    }
    function maybeFinish() {
        if (run.running) return
        if (!root.swapped) { root.phase = "held"; watchdog.restart(); return }
        root.phase = "fadeout"
        fadeOut.restart()
    }
    function swap() {
        root.swapGen = root.gen
        swapProc.command = ["caelestia", "wallpaper", "-f", root.newPath]
        swapProc.running = true
    }
    function finish() {
        fadeIn.stop(); run.stop(); fadeOut.stop(); watchdog.stop(); settle.stop()
        root.phase = "idle"; root.fade = 0; root.t = 0
        root.oldPath = ""; root.newPath = ""; root.fieldPath = ""; root.linePath = ""
    }

    NumberAnimation { id: fadeIn; target: root; property: "fade"; from: 0; to: 1
        duration: root.msFade; easing.type: Easing.OutQuad
        onFinished: root.swap() }
    NumberAnimation { id: run; target: root; property: "t"; from: 0; to: 1
        easing.type: Easing.Linear
        onFinished: root.maybeFinish() }
    NumberAnimation { id: fadeOut; target: root; property: "fade"; from: 1; to: 0
        duration: root.msFade; easing.type: Easing.OutQuad
        onFinished: root.finish() }

    property int statFrames: 0
    property real statWorst: 0
    property string lastStats: ""
    FrameAnimation {
        running: root.phase === "run"
        onRunningChanged: if (running) { root.statFrames = 0; root.statWorst = 0 }
                          else if (root.statFrames > 0)
                              root.lastStats = root.kind + ": " + root.statFrames + " frames in "
                                  + run.duration + " ms (" + Math.round(root.statFrames * 1000 / run.duration)
                                  + " fps), worst " + Math.round(root.statWorst * 1000) + " ms"
        onTriggered: { root.statFrames++; if (root.statFrames > 2) root.statWorst = Math.max(root.statWorst, frameTime) }
    }

    Process {
        id: swapProc
        onExited: (code) => {
            if (root.swapGen !== root.gen) return
            if (code === 0) { settle.restart(); return }
            const n = root.newPath
            root.finish()
            root.caelestiaSet(n)
        }
    }
    // Caelestia now has the new image; give it time to load and cross-fade before uncovering.
    Timer { id: settle; interval: root.msSettle; onTriggered: { root.swapped = true; root.maybeFinish() } }

    Timer {
        id: watchdog; interval: 4000
        onTriggered: {
            const n = root.newPath, loading = root.phase === "loading"
            root.finish()
            if (loading && n) root.caelestiaSet(n)
        }
    }

    IpcHandler {
        target: "wallfx"
        function play(oldImg: string, newImg: string, kind: string, field: string, line: string, ember: string, ink: string): string {
            root.prepare(oldImg, newImg, kind, field, line, ember, ink); return "ok"
        }
        function state(): string { return root.phase }
        function stats(): string { return root.lastStats }
        function stop(): string { root.finish(); return "ok" }
    }

    Variants {
        id: screens
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "wallfx"

            readonly property bool loaded: oldImg.status === Image.Ready && newImg.status === Image.Ready
                && fieldImg.status === Image.Ready && lineImg.status === Image.Ready
            onLoadedChanged: if (loaded) root.screenReady()

            Image { id: oldImg; visible: false; asynchronous: true; cache: false
                source: root.oldPath ? "file://" + root.oldPath : ""
                sourceSize: Qt.size(win.width, win.height); fillMode: Image.PreserveAspectCrop }
            Image { id: newImg; visible: false; asynchronous: true; cache: false
                source: root.newPath ? "file://" + root.newPath : ""
                sourceSize: Qt.size(win.width, win.height); fillMode: Image.PreserveAspectCrop }
            Image { id: fieldImg; visible: false; asynchronous: true; cache: false
                smooth: root.kind === "perfil"
                source: root.fieldPath ? "file://" + root.fieldPath : "" }
            Image { id: lineImg; visible: false; asynchronous: true; cache: false
                source: root.linePath ? "file://" + root.linePath : "" }

            // Caelestia's fill: cover the screen, centred.
            function crop(img) {
                const iw = Math.max(img.implicitWidth, 1), ih = Math.max(img.implicitHeight, 1)
                const s = Math.max(win.width / iw, win.height / ih)
                const w = win.width / (iw * s), h = win.height / (ih * s)
                return Qt.vector4d((1 - w) / 2, (1 - h) / 2, w, h)
            }

            ShaderEffect {
                anchors.fill: parent
                visible: win.loaded
                opacity: root.fade
                property var oldTex: oldImg
                property var newTex: newImg
                property var fieldTex: fieldImg
                property var lineTex: lineImg
                property real t: root.t
                property real mode: root.kind === "perfil" ? 1 : 0
                property real sw: win.width
                property real sh: win.height
                property real fw: Math.max(fieldImg.implicitWidth, 1)
                property real fh: Math.max(fieldImg.implicitHeight, 1)
                property real lw: Math.max(lineImg.implicitWidth, 1)
                property real lh: Math.max(lineImg.implicitHeight, 1)
                property real glow: root.glow
                property real lineW: root.lineW
                property real sdRange: 16
                property real seed: root.seed
                property vector4d cropOld: win.crop(oldImg)
                property vector4d cropNew: win.crop(newImg)
                property color ember: root.ember
                property color ink: root.ink
                fragmentShader: Qt.resolvedUrl("shaders/wallfx.frag.qsb")
            }
        }
    }
}
