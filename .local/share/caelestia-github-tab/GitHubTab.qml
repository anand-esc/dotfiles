pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.utils

// GitHub dashboard tab (local addition, re-applied by a pacman hook).
// Data comes from ~/.local/share/caelestia-github-tab/github-fetch.py via `gh`.
Item {
    id: root

    required property ScreenState screenState

    readonly property string fetchScript: `${Paths.home}/.local/share/caelestia-github-tab/github-fetch.py`
    // Re-check every minute until signed in / data loaded, then every 5 minutes
    readonly property int staleSecs: ghData?.ok ? 300 : 60

    property var ghData: null
    readonly property var user: ghData?.user ?? null
    readonly property var repos: (ghData?.repos ?? []).slice(0, 5)
    readonly property var notifs: (ghData?.notifications ?? []).slice(0, 5)
    readonly property int unreadCount: (ghData?.notifications ?? []).filter(n => n.unread).length
    readonly property var weeks: ghData?.calendar?.weeks ?? []
    readonly property bool notLoggedIn: ghData?.error === "notLoggedIn"

    property real now: Date.now() / 1000

    function refresh(): void {
        if (!fetchProc.running)
            fetchProc.running = true;
    }

    function openUrl(url: string): void {
        if (!url)
            return;
        root.screenState.dashboard = false;
        Quickshell.execDetached(["xdg-open", url]);
    }

    function ago(iso: string): string {
        if (!iso)
            return "";
        const s = Math.max(0, root.now - new Date(iso).getTime() / 1000);
        if (s < 60)
            return Tr.tr("just now");
        if (s < 3600)
            return Tr.tr("%1m ago").arg(Math.floor(s / 60));
        if (s < 86400)
            return Tr.tr("%1h ago").arg(Math.floor(s / 3600));
        if (s < 86400 * 30)
            return Tr.tr("%1d ago").arg(Math.floor(s / 86400));
        return new Date(iso).toLocaleDateString(Qt.locale(), "MMM d, yyyy");
    }

    function levelColour(level: int): color {
        if (level <= 0)
            return Colours.layer(Colours.palette.m3surfaceContainerHighest, 2);
        return Qt.alpha(Colours.palette.m3primary, [0, 0.3, 0.5, 0.75, 1][level]);
    }

    function isFailure(n: var): bool {
        return /\b(failed|failure|cancelled)\b/i.test(n.title);
    }

    function notifIcon(type: string): string {
        switch (type) {
        case "PullRequest":
            return "merge";
        case "Issue":
            return "adjust";
        case "Release":
            return "new_releases";
        case "Discussion":
            return "forum";
        case "CheckSuite":
            return "check_circle";
        case "Commit":
            return "commit";
        default:
            return "notifications";
        }
    }

    implicitWidth: 840
    implicitHeight: layout.implicitHeight

    Component.onCompleted: {
        if (!ghData || now - (ghData.fetchedAt ?? 0) > staleSecs)
            refresh();
    }

    Process {
        id: fetchProc

        command: ["python3", "-I", root.fetchScript]
    }

    FileView {
        id: cacheFile

        path: `${Paths.cache}/github.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.ghData = JSON.parse(text());
                if (root.now - (root.ghData.fetchedAt ?? 0) > root.staleSecs)
                    root.refresh();
            } catch (e) {
                root.refresh();
            }
        }
        onLoadFailed: root.refresh()
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            root.now = Date.now() / 1000;
            if (root.now - (root.ghData?.fetchedAt ?? 0) > root.staleSecs)
                root.refresh();
        }
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.medium

        // ---------- Not signed in / loading ----------
        StyledRect {
            visible: !root.user
            Layout.fillWidth: true
            implicitHeight: emptyCol.implicitHeight + Tokens.padding.extraLarge * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: emptyCol

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.notLoggedIn ? "key" : (fetchProc.running ? "sync" : "cloud_off")
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.notLoggedIn ? Tr.tr("Not signed in to GitHub") : (fetchProc.running ? Tr.tr("Loading GitHub...") : Tr.tr("Couldn't reach GitHub"))
                    font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.notLoggedIn ? Tr.tr("Run  gh auth login  in a terminal, then reopen this tab") : (root.ghData?.error ?? "")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // ---------- Profile header ----------
        RowLayout {
            visible: !!root.user
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.large

            ClippingRectangle {
                implicitWidth: 72
                implicitHeight: 72
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                Image {
                    anchors.fill: parent
                    source: root.user ? `file://${Paths.cache}/github-avatar.png` : ""
                    sourceSize: Qt.size(144, 144)
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: root.openUrl(root.user?.url ?? "")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.user?.name ?? ""
                    font: Tokens.font.body.builders.large.size(26).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    text: `@${root.user?.login ?? ""}`
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3primary
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.user?.bio ?? ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            Row {
                spacing: Tokens.spacing.largeIncreased

                ProfileStat {
                    value: root.user?.followers ?? 0
                    label: Tr.tr("Followers")
                }
                ProfileStat {
                    value: root.user?.following ?? 0
                    label: Tr.tr("Following")
                }
                ProfileStat {
                    value: root.user?.repoCount ?? 0
                    label: Tr.tr("Repos")
                }
            }

            StyledRect {
                implicitWidth: 40
                implicitHeight: 40
                radius: Tokens.rounding.full
                color: "transparent"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "refresh"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.large
                    rotation: fetchProc.running ? 360 : 0

                    RotationAnimation on rotation {
                        running: fetchProc.running
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: root.refresh()
                }
            }
        }

        // ---------- Contribution graph ----------
        StyledRect {
            visible: !!root.user
            Layout.fillWidth: true
            implicitHeight: calCol.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: calCol

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Tr.tr("%1 contributions in the last year").arg(root.ghData?.calendar?.total ?? 0)
                        font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                        color: Colours.palette.m3onSurface
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: Tr.tr("Updated %1").arg(root.ago(root.ghData?.fetchedAt ? new Date(root.ghData.fetchedAt * 1000).toISOString() : ""))
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        opacity: 0.7
                    }
                }

                Row {
                    id: grid

                    readonly property int gap: 3
                    readonly property int cell: Math.max(4, Math.floor((calCol.width - gap * (root.weeks.length - 1)) / Math.max(1, root.weeks.length)))

                    Layout.alignment: Qt.AlignHCenter
                    spacing: gap

                    Repeater {
                        model: root.weeks

                        Column {
                            id: week

                            required property var modelData
                            required property int index

                            spacing: grid.gap
                            // First week may start mid-week: push it down so weekdays line up
                            topPadding: week.index === 0 ? (7 - week.modelData.length) * (grid.cell + grid.gap) : 0

                            Repeater {
                                model: week.modelData

                                Rectangle {
                                    id: day

                                    required property var modelData

                                    implicitWidth: grid.cell
                                    implicitHeight: grid.cell
                                    radius: Math.max(2, grid.cell / 4)
                                    color: root.levelColour(day.modelData.level)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: Tr.tr("Less")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    Repeater {
                        model: 5

                        Rectangle {
                            required property int index

                            implicitWidth: 12
                            implicitHeight: 12
                            radius: 3
                            color: root.levelColour(index)
                        }
                    }

                    StyledText {
                        text: Tr.tr("More")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        // ---------- Repos + notifications ----------
        RowLayout {
            visible: !!root.user
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            ListCard {
                title: Tr.tr("Recent repositories")
                icon: "book"

                Repeater {
                    model: root.repos

                    ListRow {
                        id: repo

                        required property var modelData

                        onActivated: root.openUrl(repo.modelData.url)

                        MaterialIcon {
                            Layout.alignment: Qt.AlignVCenter
                            text: repo.modelData.private ? "lock" : (repo.modelData.fork ? "fork_right" : "book")
                            color: Colours.palette.m3secondary
                            fontStyle: Tokens.font.icon.medium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: repo.modelData.name
                                font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                                color: Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: Tokens.spacing.small

                                Rectangle {
                                    visible: repo.modelData.language.length > 0
                                    implicitWidth: 8
                                    implicitHeight: 8
                                    radius: 4
                                    color: repo.modelData.languageColor || Colours.palette.m3outline
                                }

                                StyledText {
                                    text: [repo.modelData.language, root.ago(repo.modelData.pushedAt)].filter(s => s).join("  ·  ")
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }

                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            visible: repo.modelData.stars > 0

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "star"
                                color: Colours.palette.m3tertiary
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: repo.modelData.stars
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }
            }

            ListCard {
                title: Tr.tr("Notifications")
                icon: "notifications"
                badge: root.unreadCount

                StyledText {
                    visible: root.notifs.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.padding.large
                    horizontalAlignment: Text.AlignHCenter
                    text: Tr.tr("All caught up")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                Repeater {
                    model: root.notifs

                    ListRow {
                        id: notif

                        required property var modelData

                        onActivated: root.openUrl(notif.modelData.url)

                        MaterialIcon {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.isFailure(notif.modelData) ? "error" : root.notifIcon(notif.modelData.type)
                            color: root.isFailure(notif.modelData) ? Colours.palette.m3error : (notif.modelData.unread ? Colours.palette.m3primary : Colours.palette.m3outline)
                            fontStyle: Tokens.font.icon.medium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: notif.modelData.title
                                font: Tokens.font.body.builders.small.weight(notif.modelData.unread ? Font.DemiBold : Font.Normal).build()
                                color: Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `${notif.modelData.repo}  ·  ${root.ago(notif.modelData.updatedAt)}`
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: notif.modelData.unread
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: Colours.palette.m3primary
                        }
                    }
                }
            }
        }
    }

    component ProfileStat: Column {
        id: stat

        property int value
        property string label

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stat.value
            font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
            color: Colours.palette.m3primary
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: stat.label
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    component ListCard: StyledRect {
        id: card

        property string title
        property string icon
        property int badge
        default property alias content: cardItems.data

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        implicitHeight: cardCol.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: cardCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.leftMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: card.icon
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    text: card.title
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledRect {
                    visible: card.badge > 0
                    implicitWidth: Math.max(implicitHeight, badgeText.implicitWidth + Tokens.padding.small * 2)
                    implicitHeight: badgeText.implicitHeight + 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    StyledText {
                        id: badgeText

                        anchors.centerIn: parent
                        text: card.badge
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        color: Colours.palette.m3onPrimary
                    }
                }
            }

            ColumnLayout {
                id: cardItems

                Layout.fillWidth: true
                spacing: 0
            }
        }
    }

    component ListRow: StyledRect {
        id: row

        signal activated
        default property alias content: rowItems.data

        Layout.fillWidth: true
        implicitHeight: rowItems.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.medium
        color: "transparent"

        StateLayer {
            radius: Tokens.rounding.medium
            onClicked: row.activated()
        }

        RowLayout {
            id: rowItems

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.small
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.medium
        }
    }
}
