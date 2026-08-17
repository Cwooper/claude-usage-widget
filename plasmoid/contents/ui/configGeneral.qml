import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_pollMinutes: pollMinutes.value
    property alias cfg_showSessionRing: showSessionRing.checked
    property alias cfg_showWeeklyRings: showWeeklyRings.checked
    property alias cfg_showModelBar: showModelBar.checked
    property alias cfg_showCountdown: showCountdown.checked
    property alias cfg_showLabels: showLabels.checked
    property alias cfg_showPaceTick: showPaceTick.checked
    property alias cfg_modelBarHeight: modelBarHeight.value
    property alias cfg_ringThickness: ringThickness.value

    QQC2.SpinBox {
        id: pollMinutes
        Kirigami.FormData.label: i18n("Update every:")
        from: 1
        to: 60
        textFromValue: (value) => i18np("%1 minute", "%1 minutes", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.CheckBox {
        id: showSessionRing
        Kirigami.FormData.label: i18n("Show:")
        text: i18n("Session ring")
    }

    QQC2.CheckBox {
        id: showWeeklyRings
        text: i18n("Weekly rings")
    }

    QQC2.CheckBox {
        id: showModelBar
        text: i18n("Model token bar")
    }

    QQC2.CheckBox {
        id: showPaceTick
        text: i18n("Pace marker")
    }

    QQC2.CheckBox {
        id: showCountdown
        text: i18n("Time until reset")
    }

    QQC2.CheckBox {
        id: showLabels
        text: i18n("Caption under each ring")
    }

    Item {
        Kirigami.FormData.isSection: true
    }

    QQC2.SpinBox {
        id: modelBarHeight
        Kirigami.FormData.label: i18n("Model bar height:")
        from: 6
        to: 96
        enabled: showModelBar.checked
        textFromValue: (value) => i18np("%1 point", "%1 points", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.SpinBox {
        id: ringThickness
        Kirigami.FormData.label: i18n("Ring thickness:")
        from: 4
        to: 25
        textFromValue: (value) => i18n("%1% of diameter", value)
        valueFromText: (text) => parseInt(text, 10)
    }
}
