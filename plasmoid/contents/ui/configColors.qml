import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    id: page

    property alias cfg_useThemeColors: useThemeColors.checked
    property alias cfg_colorUnderPace: colorUnderPace.color
    property alias cfg_colorNearPace: colorNearPace.color
    property alias cfg_colorOverPace: colorOverPace.color
    property alias cfg_colorAhead: colorAhead.color
    property alias cfg_colorOnPace: colorOnPace.color
    property alias cfg_modelBarColor: modelBarColor.color
    property alias cfg_nearPaceThreshold: nearPaceThreshold.value
    property alias cfg_overPaceThreshold: overPaceThreshold.value

    QQC2.CheckBox {
        id: useThemeColors
        Kirigami.FormData.label: i18n("Pace colours:")
        text: i18n("Follow the desktop theme")
    }

    KQuickControls.ColorButton {
        id: colorUnderPace
        Kirigami.FormData.label: i18n("Under pace:")
        enabled: !useThemeColors.checked
        showAlphaChannel: false
    }

    KQuickControls.ColorButton {
        id: colorNearPace
        Kirigami.FormData.label: i18n("Over pace:")
        enabled: !useThemeColors.checked
        showAlphaChannel: false
    }

    KQuickControls.ColorButton {
        id: colorOverPace
        Kirigami.FormData.label: i18n("Well over pace:")
        enabled: !useThemeColors.checked
        showAlphaChannel: false
    }

    KQuickControls.ColorButton {
        id: colorAhead
        Kirigami.FormData.label: i18n("Marker, ahead:")
        enabled: !useThemeColors.checked
        showAlphaChannel: false
    }

    KQuickControls.ColorButton {
        id: colorOnPace
        Kirigami.FormData.label: i18n("Marker, on pace:")
        enabled: !useThemeColors.checked
        showAlphaChannel: false
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    KQuickControls.ColorButton {
        id: modelBarColor
        Kirigami.FormData.label: i18n("Model bar:")
        showAlphaChannel: false
    }

    QQC2.Label {
        text: i18n("Shaded from this colour, darkest model first.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: nearPaceThreshold
        Kirigami.FormData.label: i18n("Over pace above:")
        from: 0
        // Past the well-over threshold the over-pace colour is unreachable and
        // its button appears to do nothing.
        to: overPaceThreshold.value
        textFromValue: (value) => i18np("%1 point", "%1 points", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.SpinBox {
        id: overPaceThreshold
        Kirigami.FormData.label: i18n("Well over pace above:")
        from: 1
        to: 75
        textFromValue: (value) => i18np("%1 point", "%1 points", value)
        valueFromText: (text) => parseInt(text, 10)
    }
}
