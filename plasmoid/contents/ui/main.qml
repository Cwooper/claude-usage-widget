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

    readonly property string probeCommand: "$HOME/.local/bin/claude-usage-probe"
    readonly property int pollInterval: 5 * 60 * 1000

    property var gauges: []
    property var models: []
    property bool stale: false
    property bool everLoaded: false

    // Advances the pace marker and countdowns between probes, which are far
    // too expensive to run at display refresh rates.
    property double now: 0

    readonly property var labels: ({
        "session": "session",
        "week": "week"
    })

    readonly property var sessionGauge: {
        for (const gauge of gauges) {
            if (gauge.key === "session") {
                return gauge;
            }
        }
        return null;
    }

    readonly property var otherGauges: gauges.filter(gauge => gauge.key !== "session")

    function labelFor(key) {
        return labels[key] !== undefined ? labels[key] : key;
    }

    function paceOf(gauge) {
        if (!gauge.windowSeconds || !gauge.resetsAt) {
            return 0;
        }
        const elapsed = gauge.windowSeconds - (gauge.resetsAt - root.now);
        return Math.max(0, Math.min(1, elapsed / gauge.windowSeconds));
    }

    function secondsLeft(gauge) {
        return Math.max(0, gauge.resetsAt - root.now);
    }

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
        const lines = gauges.map(g => labelFor(g.key) + ": " + g.pct + "% used, resets in "
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
                if (!pick || gauge.pct > pick.pct) {
                    pick = gauge;
                }
            }
            return pick;
        }

        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2

        onClicked: root.expanded = !root.expanded

        Gauge {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            captions: false
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

        PlasmaComponents.Label {
            anchors.centerIn: parent
            visible: !root.everLoaded
            text: "Waiting for first reading..."
            opacity: 0.6
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            visible: root.everLoaded
            spacing: Kirigami.Units.largeSpacing
            opacity: root.stale ? 0.5 : 1

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing

                Gauge {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    // The session window is the one that actually stops work, so
                    // it gets roughly double the diameter of the weekly pair.
                    Layout.preferredWidth: 10
                    visible: root.sessionGauge !== null
                    label: root.labelFor(root.sessionGauge ? root.sessionGauge.key : "")
                    pct: root.sessionGauge ? root.sessionGauge.pct : 0
                    pace: root.sessionGauge ? root.paceOf(root.sessionGauge) : 0
                    secondsLeft: root.sessionGauge ? root.secondsLeft(root.sessionGauge) : 0
                }

                Kirigami.Separator {
                    Layout.fillHeight: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.bottomMargin: Kirigami.Units.gridUnit
                    opacity: 0.5
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 11
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: root.otherGauges

                        Gauge {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            label: root.labelFor(modelData.key)
                            pct: modelData.pct
                            pace: root.paceOf(modelData)
                            secondsLeft: root.secondsLeft(modelData)
                        }
                    }
                }
            }

            ModelBar {
                Layout.fillWidth: true
                models: root.models
            }
        }
    }
}
