pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "formatter.js" as Formatter

PlasmoidItem {
    id: root

    // Run through python3 rather than executing directly: a published .plasmoid
    // installs from a zip, which does not carry the executable bit.
    readonly property string probeCommand: {
        // A URL, so percent-encoded; and the engine runs this through a shell,
        // so an apostrophe in the install path would close the quote early.
        const url = Qt.resolvedUrl("../bin/claude-usage-probe").toString();
        const path = decodeURIComponent(url.replace(/^file:\/\//, ""));
        return "python3 '" + path.replace(/'/g, "'\\''") + "'";
    }
    readonly property int pollInterval: Plasmoid.configuration.pollMinutes * 60 * 1000

    property var gauges: []
    property var models: []
    property bool stale: false
    property bool everLoaded: false
    property bool busy: false
    property bool probed: false
    property string errorText: ""

    // Advances the pace marker and countdowns between probes, which are far
    // too expensive to run at display refresh rates.
    property double now: 0

    readonly property var sessionGauge: {
        for (const gauge of gauges) {
            if (gauge.key === "session") {
                return gauge;
            }
        }
        return null;
    }

    readonly property var otherGauges: gauges.filter(gauge => gauge.key !== "session")

    function paceOf(gauge) {
        if (!gauge.windowSeconds || !gauge.resetsAt) {
            return 0;
        }
        const elapsed = gauge.windowSeconds - (gauge.resetsAt - root.now);
        return Math.max(0, Math.min(1, elapsed / gauge.windowSeconds));
    }

    // Mirrors Gauge's own `delta`; the panel ring ranks on it so the collapsed
    // and expanded views cannot disagree about which window is worst.
    function paceDelta(gauge) {
        return gauge.pct / 100 - paceOf(gauge);
    }

    // Guarded: connectSource on an already-connected source is a no-op, so a
    // second click during a probe would look ignored rather than queued.
    function refresh() {
        if (busy) {
            return;
        }
        busy = true;
        probe.connectSource(probeCommand);
    }

    function secondsLeft(gauge) {
        if (!gauge.resetsAt) {
            return 0;
        }
        return Math.max(0, gauge.resetsAt - root.now);
    }

    // Two blanks stand in for the weekly rings until the first reading, so the
    // unloaded widget has the same skeleton as the loaded one.
    // Distinguishes "not probed yet" from "probed and got nothing", which
    // otherwise both render as an endless spinner.
    readonly property bool failed: probed && !everLoaded

    readonly property var weeklyModel: everLoaded ? otherGauges : [{}, {}]


    P5Support.DataSource {
        id: probe
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);
            root.busy = false;
            root.probed = true;
            if (data["exit code"] !== 0) {
                root.stale = true;
                root.errorText = (data.stderr || "").trim()
                                 || i18n("Could not start the usage probe.");
                return;
            }
            try {
                const payload = JSON.parse(data.stdout);
                root.gauges = payload.gauges || [];
                root.models = payload.models || [];
                root.stale = !!payload.stale;
                root.errorText = (payload.errors || []).join("\n");
                root.everLoaded = root.gauges.length > 0;
            } catch (e) {
                root.stale = true;
                root.errorText = i18n("The usage probe returned unreadable output.");
            }
        }
    }


    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now() / 1000
    }

    toolTipMainText: i18n("Claude Usage")
    toolTipSubText: {
        if (failed) {
            return errorText;
        }
        if (!everLoaded) {
            return i18n("Waiting for first reading...");
        }
        const lines = gauges.map(g => g.inactive
                                 ? g.key + ": " + i18n("idle")
                                 : g.key + ": " + g.pct + "% used, resets in "
                                   + Formatter.duration(secondsLeft(g)));
        if (models.length > 0) {
            lines.push(i18n("Output tokens this week: ")
                       + models.map(m => m.name + " " + Formatter.tokens(m.tokens)).join(", "));
        }
        if (stale) {
            lines.push(errorText || i18n("(last known values; probe failed)"));
        }
        return lines.join("\n");
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    compactRepresentation: MouseArea {
        readonly property var worst: {
            let pick = null;
            for (const gauge of root.gauges) {
                // Ranking a window that is not running would let the panel ring
                // sit at 0 while a weekly window burns.
                if (gauge.inactive) {
                    continue;
                }
                if (!pick || root.paceDelta(gauge) > root.paceDelta(pick)) {
                    pick = gauge;
                }
            }
            return pick;
        }

        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2

        onClicked: root.expanded = !root.expanded

        StyledGauge {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            captions: false
            // A failed probe leaves no reading to wait for; spinning here would
            // read as a probe still in flight.
            loading: !root.everLoaded && !root.failed
            opacity: root.stale ? 0.5 : 1
            pct: parent.worst ? parent.worst.pct : 0
            pace: parent.worst ? root.paceOf(parent.worst) : 0
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Kirigami.Units.gridUnit * 10

        Item {
            id: refreshButton

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.smallSpacing
            width: Kirigami.Units.iconSizes.small
            height: width
            z: 1
            // Dimmed rather than animated while probing: a spinning arrow at any
            // speed reads as frantic next to the ring spinner.
            opacity: root.busy ? 0.2 : (refreshArea.containsMouse ? 1 : 0.35)

            Kirigami.Icon {
                anchors.fill: parent
                source: "view-refresh"
            }

            MouseArea {
                id: refreshArea
                anchors.fill: parent
                enabled: !root.busy
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
                QQC2.ToolTip.visible: refreshArea.containsMouse
                QQC2.ToolTip.text: i18n("Refresh now")
            }
        }

        PlasmaComponents.Label {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            visible: root.failed
            text: root.errorText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            opacity: 0.8
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            visible: !root.failed
            spacing: Kirigami.Units.largeSpacing
            opacity: root.stale ? 0.5 : 1

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                StyledGauge {
                    id: sessionRing

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Equal stretch against a pair of gauges, so the session
                    // window -- the one that actually stops work -- draws at
                    // double their diameter.
                    Layout.horizontalStretchFactor: 2
                    visible: (root.sessionGauge !== null || !root.everLoaded)
                             && Plasmoid.configuration.showSessionRing
                    loading: !root.everLoaded
                    inactive: root.sessionGauge !== null && !!root.sessionGauge.inactive
                    inactiveOpacity: root.stale ? 1 : 0.5
                    label: root.sessionGauge ? root.sessionGauge.key : ""
                    pct: root.sessionGauge ? root.sessionGauge.pct : 0
                    pace: root.sessionGauge ? root.paceOf(root.sessionGauge) : 0
                    secondsLeft: root.sessionGauge ? root.secondsLeft(root.sessionGauge) : 0
                }

                Kirigami.Separator {
                    // Off the ring's own visibility, not the setting: a probe
                    // failure can leave no session gauge to draw beside it.
                    visible: sessionRing.visible
                             && Plasmoid.configuration.showWeeklyRings
                             && root.weeklyModel.length > 0
                    Layout.fillHeight: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.bottomMargin: Kirigami.Units.gridUnit
                    opacity: 0.5
                }

                RowLayout {
                    visible: Plasmoid.configuration.showWeeklyRings
                             && root.weeklyModel.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.horizontalStretchFactor: 2
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.weeklyModel

                        StyledGauge {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            loading: !root.everLoaded
                            label: modelData.key !== undefined ? modelData.key : ""
                            pct: modelData.pct !== undefined ? modelData.pct : 0
                            pace: root.paceOf(modelData)
                            secondsLeft: root.secondsLeft(modelData)
                        }
                    }
                }
            }

            ModelBar {
                visible: Plasmoid.configuration.showModelBar
                Layout.fillWidth: true
                loading: !root.everLoaded
                models: root.models
                baseColor: Plasmoid.configuration.modelBarColor
                barHeight: Plasmoid.configuration.modelBarHeight
            }
        }
    }
}
