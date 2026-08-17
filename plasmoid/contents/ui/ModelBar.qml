pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "formatter.js" as Formatter

Item {
    id: root

    // [{ name: "opus", tokens: 3488621 }, ...]
    property var models: []

    readonly property real total: {
        let sum = 0;
        for (const entry of models) {
            sum += entry.tokens;
        }
        return sum;
    }

    // One hue rather than four: these are slices of a single measure, and a
    // categorical palette oversells the difference between them. Keyed by
    // family, not by position, so a model keeps its shade as the mix shifts
    // week to week.
    readonly property color baseColor: "#d97757"
    readonly property var families: ["fable", "opus", "sonnet", "haiku"]

    function shadeFor(name) {
        const rank = families.indexOf(name);
        if (rank < 0) {
            return Kirigami.Theme.disabledTextColor;
        }
        // Qt.darker lightens below 1.0, so one expression walks the whole ramp
        // from fable (darkest) to haiku (lightest).
        return Qt.darker(baseColor, 1.6 - rank * 0.3);
    }

    implicitHeight: Kirigami.Units.gridUnit

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
        visible: root.total <= 0
    }

    Row {
        id: segments
        anchors.fill: parent
        visible: root.total > 0

        Repeater {
            model: root.models

            Rectangle {
                id: segment

                required property var modelData

                width: segments.width * (segment.modelData.tokens / root.total)
                height: segments.height
                color: root.shadeFor(segment.modelData.name)

                PlasmaComponents.Label {
                    id: segmentLabel
                    anchors.centerIn: parent
                    visible: segment.width > segmentLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                    text: segment.modelData.name + " " + Formatter.tokens(segment.modelData.tokens)
                    color: Formatter.textOn(segment.color)
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }
            }
        }
    }
}
