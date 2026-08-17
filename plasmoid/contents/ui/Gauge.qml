import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "formatter.js" as Formatter

ColumnLayout {
    id: root

    property string label: ""
    property real pct: 0
    property real pace: 0
    property real secondsLeft: 0
    property bool captions: true
    property bool idle: false

    property bool showCountdown: true
    property bool showLabel: true
    property bool showTick: true
    property real thickness: 0.1
    property int spinDuration: 4400

    property bool themeColors: true
    property color underColor: Kirigami.Theme.positiveTextColor
    property color nearColor: Kirigami.Theme.neutralTextColor
    property color overColor: Kirigami.Theme.negativeTextColor
    property color aheadColor: Kirigami.Theme.textColor
    property color onPaceColor: themePaceColor
    property real nearThreshold: 0
    property real overThreshold: 0.15

    spacing: 0

    // Pace-relative: 79% is fine six days into a week, alarming six hours in.
    readonly property real delta: pct / 100 - Math.min(1, pace)

    // Breeze's highlight reads as white at tick width, so the "on pace" blue is
    // saturated rather than darkened -- darkening it far enough to separate from
    // white turned it muddy.
    readonly property color themePaceColor: {
        const accent = Kirigami.Theme.highlightColor;
        return Qt.hsla(accent.hslHue,
                       Math.min(1, accent.hslSaturation * 1.4),
                       Math.min(1, accent.hslLightness * 1.05),
                       1);
    }

    readonly property color valueColor: delta <= nearThreshold ? underColor
                                      : delta <= overThreshold ? nearColor
                                      : overColor

    readonly property color tickColor: delta <= -0.05 ? aheadColor
                                     : delta <= Math.max(0.05, nearThreshold) ? onPaceColor
                                     : delta <= overThreshold ? nearColor
                                     : overColor

    // Named so a theme change repaints the Canvas; read directly it would not.
    readonly property color trackColor: Qt.alpha(Kirigami.Theme.textColor, 0.15)
    readonly property color outlineColor: Kirigami.Theme.backgroundColor
    readonly property color spinnerColor: Kirigami.Theme.highlightColor

    Item {
        id: ring

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2

        readonly property real size: Math.min(width, height)

        Canvas {
            id: canvas
            anchors.fill: parent
            visible: !root.idle
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const cx = width / 2;
                const cy = height / 2;
                const thickness = Math.max(3, ring.size * root.thickness);
                const radius = ring.size / 2 - thickness / 2 - 1;
                if (radius <= 0) {
                    return;
                }
                const top = -Math.PI / 2;

                ctx.lineWidth = thickness;


                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
                ctx.strokeStyle = root.trackColor;
                ctx.stroke();

                const sweep = 2 * Math.PI * Math.max(0, Math.min(1, root.pct / 100));
                if (sweep > 0) {
                    ctx.beginPath();
                    ctx.arc(cx, cy, radius, top, top + sweep);
                    ctx.strokeStyle = root.valueColor;
                    ctx.stroke();
                }

                if (!root.showTick) {
                    return;
                }

                const paceAngle = top + 2 * Math.PI * Math.max(0, Math.min(1, root.pace));
                const inner = radius - thickness / 2 - 3;
                const outer = radius + thickness / 2 + 3;
                const tickWidth = Math.max(2, thickness * 0.3);

                // Drawn twice: the tick's colour can equal the arc's underneath
                // it (red on red, amber on amber), so it needs its own outline to
                // stay visible.
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(paceAngle) * inner, cy + Math.sin(paceAngle) * inner);
                ctx.lineTo(cx + Math.cos(paceAngle) * outer, cy + Math.sin(paceAngle) * outer);
                ctx.lineWidth = tickWidth + Math.max(2, thickness * 0.22);
                ctx.strokeStyle = root.outlineColor;
                ctx.stroke();

                ctx.lineWidth = tickWidth;
                ctx.strokeStyle = root.tickColor;
                ctx.stroke();
            }

            Connections {
                target: root
                function onPctChanged() { canvas.requestPaint(); }
                function onPaceChanged() { canvas.requestPaint(); }
                function onValueColorChanged() { canvas.requestPaint(); }
                function onTickColorChanged() { canvas.requestPaint(); }
                function onShowTickChanged() { canvas.requestPaint(); }
                function onThicknessChanged() { canvas.requestPaint(); }
                function onIdleChanged() { canvas.requestPaint(); }
                function onTrackColorChanged() { canvas.requestPaint(); }
                function onOutlineColorChanged() { canvas.requestPaint(); }
            }
        }

        Canvas {
            id: spinner
            anchors.fill: parent
            visible: root.idle
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();

                const cx = width / 2;
                const cy = height / 2;
                const thickness = Math.max(3, ring.size * root.thickness);
                const radius = ring.size / 2 - thickness / 2 - 1;
                if (radius <= 0) {
                    return;
                }
                ctx.lineWidth = thickness;

                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
                ctx.strokeStyle = root.trackColor;
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, radius, -Math.PI / 2, 0);
                ctx.strokeStyle = root.spinnerColor;
                ctx.stroke();
            }

            // Rotating the item is GPU-side; repainting the arc each frame is not.
            RotationAnimator on rotation {
                running: root.idle
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: root.spinDuration
            }

            Connections {
                target: root
                function onThicknessChanged() { spinner.requestPaint(); }
                function onTrackColorChanged() { spinner.requestPaint(); }
                function onSpinnerColorChanged() { spinner.requestPaint(); }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            // The text has to clear the arc on both sides, so it is bounded by
            // the square inscribed in the ring's inner circle, not by its width.
            width: ring.size * 0.55
            spacing: -ring.size * 0.03

            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: !root.idle
                text: Math.round(root.pct)
                color: root.valueColor
                font.pixelSize: Math.max(9, ring.size * 0.33)
                font.weight: Font.DemiBold
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                // Drops out on the compact panel ring, where it would be illegible.
                visible: !root.idle && root.captions && root.showCountdown && ring.size >= 40
                text: Formatter.duration(root.secondsLeft, ring.size < 96)
                opacity: 0.55
                font.pixelSize: Math.max(8, ring.size * 0.13)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 7
                elide: Text.ElideRight
            }
        }
    }

    PlasmaComponents.Label {
        visible: root.captions && root.showLabel
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.label
        opacity: 0.8
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.5
    }
}
