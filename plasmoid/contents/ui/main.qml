pragma ComponentBehavior: Bound

import QtQuick
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
        const path = Qt.resolvedUrl("../bin/claude-usage-probe")
                       .toString().replace(/^file:\/\//, "");
        return "python3 '" + path + "'";
    }
    readonly property int pollInterval: Plasmoid.configuration.pollMinutes * 60 * 1000

    property var gauges: []
    property var models: []
    property bool stale: false
    property bool everLoaded: false

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

    function secondsLeft(gauge) {
        if (!gauge.resetsAt) {
            return 0;
        }
        return Math.max(0, gauge.resetsAt - root.now);
    }

    // Two blanks stand in for the weekly rings until the first reading, so the
    // idle widget has the same skeleton as the loaded one.
    readonly property var weeklyModel: everLoaded ? otherGauges : [{}, {}]


    P5Support.DataSource {
        id: probe
        engine: "executable"
        connectedSources: []

        onNewData: function (source, data) {
            disconnectSource(source);
            if (data["exit code"] !== 0) {
                root.stale = true;
                return;
            }
            try {
                const payload = JSON.parse(data.stdout);
                root.gauges = payload.gauges || [];
                root.models = payload.models || [];
                root.stale = !!payload.stale;
                root.everLoaded = true;
            } catch (e) {
                root.stale = true;
            }
        }
    }


    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.connectSource(root.probeCommand)
    }

    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now() / 1000
    }

    toolTipMainText: "Claude Usage"
    toolTipSubText: {
        if (!everLoaded) {
            return "Waiting for first reading...";
        }
        const lines = gauges.map(g => g.key + ": " + g.pct + "% used, resets in "
                                 + Formatter.duration(secondsLeft(g)));
        if (models.length > 0) {
            lines.push("Output tokens this week: "
                       + models.map(m => m.name + " " + Formatter.tokens(m.tokens)).join(", "));
        }
        if (stale) {
            lines.push("(last known values; probe failed)");
        }
        return lines.join("\n");
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground

    compactRepresentation: MouseArea {
        readonly property var worst: {
            let pick = null;
            for (const gauge of root.gauges) {
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
            idle: !root.everLoaded
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing
            opacity: root.stale ? 0.5 : 1

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                StyledGauge {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // Equal stretch against a pair of gauges, so the session
                    // window -- the one that actually stops work -- draws at
                    // double their diameter.
                    Layout.horizontalStretchFactor: 2
                    visible: (root.sessionGauge !== null || !root.everLoaded)
                             && Plasmoid.configuration.showSessionRing
                    idle: !root.everLoaded
                    label: root.sessionGauge ? root.sessionGauge.key : ""
                    pct: root.sessionGauge ? root.sessionGauge.pct : 0
                    pace: root.sessionGauge ? root.paceOf(root.sessionGauge) : 0
                    secondsLeft: root.sessionGauge ? root.secondsLeft(root.sessionGauge) : 0
                }

                Kirigami.Separator {
                    visible: Plasmoid.configuration.showSessionRing
                             && Plasmoid.configuration.showWeeklyRings
                             && root.weeklyModel.length > 0
                    Layout.fillHeight: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.bottomMargin: Kirigami.Units.gridUnit
                    opacity: 0.5
                }

                RowLayout {
                    visible: Plasmoid.configuration.showWeeklyRings
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
                            idle: !root.everLoaded
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
                idle: !root.everLoaded
                models: root.models
                baseColor: Plasmoid.configuration.modelBarColor
                barHeight: Plasmoid.configuration.modelBarHeight
            }
        }
    }
}
