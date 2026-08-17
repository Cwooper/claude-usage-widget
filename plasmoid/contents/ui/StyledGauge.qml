import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

// Gauge with the configuration applied, so the three call sites do not each
// repeat the same dozen bindings. Gauge itself stays configuration-agnostic.
Gauge {
    id: styled

    readonly property bool themed: Plasmoid.configuration.useThemeColors

    showCountdown: Plasmoid.configuration.showCountdown
    showLabel: Plasmoid.configuration.showLabels
    showTick: Plasmoid.configuration.showPaceTick
    thickness: Plasmoid.configuration.ringThickness / 100

    nearThreshold: Plasmoid.configuration.nearPaceThreshold / 100
    overThreshold: Plasmoid.configuration.overPaceThreshold / 100

    underColor: themed ? Kirigami.Theme.positiveTextColor : Plasmoid.configuration.colorUnderPace
    nearColor: themed ? Kirigami.Theme.neutralTextColor : Plasmoid.configuration.colorNearPace
    overColor: themed ? Kirigami.Theme.negativeTextColor : Plasmoid.configuration.colorOverPace
    aheadColor: themed ? Kirigami.Theme.textColor : Plasmoid.configuration.colorAhead
    onPaceColor: themed ? styled.themePaceColor : Plasmoid.configuration.colorOnPace
}
