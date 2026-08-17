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

    // Keyed by family, not position, so a model keeps its shade as the mix shifts.
    property color baseColor: "#d97757"
    readonly property var families: ["fable", "opus", "sonnet", "haiku"]

    function shadeFor(name) {
        const rank = families.indexOf(name);
        if (rank < 0) {
            return Kirigami.Theme.disabledTextColor;
        }
        // Qt.darker lightens below 1.0, so one expression spans the whole ramp.
        return Qt.darker(baseColor, 1.6 - rank * 0.3);
    }

    property bool idle: false
    property int barHeight: Kirigami.Units.gridUnit

    implicitHeight: barHeight

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Kirigami.Theme.textColor, 0.12)
        visible: root.idle || root.total <= 0
        clip: true

        Rectangle {
            id: shimmer
            width: parent.width * 0.28
            height: parent.height
            visible: root.idle
            color: Qt.alpha(Kirigami.Theme.highlightColor, 0.55)

            XAnimator on x {
                running: root.idle
                loops: Animation.Infinite
                from: -shimmer.width
                to: shimmer.parent.width
                duration: 1400
            }
        }
    }


    Row {
        id: segments
        anchors.fill: parent
        visible: !root.idle && root.total > 0

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
