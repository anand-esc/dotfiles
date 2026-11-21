pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// Night light bar pill (local addition, re-applied by a pacman hook).
//   Click        : Off -> Warm -> Night -> Cool -> Off
//   Scroll       : fine-tune temperature (250 K steps)
//   Right-click  : Off
// Backend: hyprsunset (started on demand). State persists in ~/.local/state/caelestia/nightlight.json
StyledRect {
    id: root

    readonly property var modes: [
        { name: "Off",   temp: 6500, icon: "nightlight",   colour: Colours.palette.m3onSurfaceVariant },
        { name: "Warm",  temp: 4500, icon: "wb_twilight",  colour: "#ffc35a" },
        { name: "Night", temp: 3500, icon: "bedtime",      colour: "#ff9a4d" },
        { name: "Cool",  temp: 7500, icon: "ac_unit",      colour: "#7fb2ff" }
    ]

    property bool enabled: false
    property int temp: 4500
    property bool loaded: false

    readonly property int modeIndex: {
        if (!enabled)
            return 0;
        // closest named mode, for the icon/colour
        let best = 1;
        for (let i = 1; i < modes.length; i++)
            if (Math.abs(modes[i].temp - temp) < Math.abs(modes[best].temp - temp))
                best = i;
        return best;
    }
    readonly property var mode: modes[modeIndex]
    readonly property color tint: enabled ? (temp > 6500 ? "#7fb2ff" : temp > 4000 ? "#ffc35a" : "#ff9a4d") : modes[0].colour

    function apply(): void {
        const cmd = enabled
            ? `hyprctl hyprsunset temperature ${temp}`
            : "hyprctl hyprsunset identity";
        applyProc.command = ["sh", "-c",
            `pgrep -x hyprsunset >/dev/null || { setsid -f hyprsunset >/dev/null 2>&1; sleep 0.8; }; ${cmd} >/dev/null`];
        applyProc.running = true;
        if (loaded)
            stateFile.setText(JSON.stringify({ enabled, temp }));
    }

    function setMode(i: int): void {
        enabled = i !== 0;
        if (enabled)
            temp = modes[i].temp;
        apply();
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.medium * 2

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    Process {
        id: applyProc
    }

    FileView {
        id: stateFile

        path: `${Paths.state}/nightlight.json`
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.enabled = !!s.enabled;
                root.temp = Math.max(2500, Math.min(8000, s.temp ?? 4500));
            } catch (e) {}
            root.loaded = true;
            root.apply();
        }
        onLoadFailed: {
            root.loaded = true;
        }
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: root.mode.icon
            color: root.tint
            fill: root.enabled ? 1 : 0

            Behavior on color {
                CAnim {}
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.enabled
            text: `${(root.temp / 1000).toFixed(root.temp % 1000 === 0 ? 0 : 1)}k`
            font: Tokens.font.body.builders.small.scale(0.9).build()
            color: root.tint
        }
    }

    StateLayer {
        radius: Tokens.rounding.full
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: e => {
            if (e.button === Qt.RightButton)
                root.setMode(0);
            else
                root.setMode((root.modeIndex + 1) % root.modes.length);
        }

        onWheel: e => {
            const step = e.angleDelta.y > 0 ? -250 : 250; // scroll up = warmer
            if (!root.enabled) {
                root.enabled = true;
                root.temp = 6500;
            }
            root.temp = Math.max(2500, Math.min(8000, root.temp + step));
            root.apply();
        }
    }
}
