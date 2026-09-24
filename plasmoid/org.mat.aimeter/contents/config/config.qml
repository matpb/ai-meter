import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Meters")
        icon: "speedometer"
        source: "configMeters.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-color"
        source: "configAppearance.qml"
    }
}
