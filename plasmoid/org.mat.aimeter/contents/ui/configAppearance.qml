import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_showAppIcon: showAppIcon.checked
    property alias cfg_monochromeIcon: monochromeIcon.checked
    property alias cfg_showWindowLabels: showWindowLabels.checked
    property int cfg_panelBars
    property int cfg_refreshSec

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.CheckBox {
            id: showAppIcon
            Kirigami.FormData.label: i18n("Panel:")
            text: i18n("Always show the AI Meter icon")
        }
        QQC2.Label {
            Layout.fillWidth: true
            opacity: 0.7
            wrapMode: Text.WordWrap
            text: i18n("The icon always shows when no subscription is pinned to the panel, regardless of this setting.")
        }

        QQC2.CheckBox {
            id: monochromeIcon
            text: i18n("Tint icons to match the panel instead of brand colours")
        }

        QQC2.CheckBox {
            id: showWindowLabels
            text: i18n("Show window labels (\"5h\", \"7d\"…) next to bars")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: panelBars
            Kirigami.FormData.label: i18n("Bars per pinned subscription:")
            from: 1
            to: 3
            value: cfg_panelBars
            onValueModified: cfg_panelBars = value
        }

        QQC2.SpinBox {
            id: refreshSec
            Kirigami.FormData.label: i18n("Refresh interval (seconds):")
            from: 30
            to: 600
            stepSize: 10
            value: cfg_refreshSec
            onValueModified: cfg_refreshSec = value
        }
    }
}
