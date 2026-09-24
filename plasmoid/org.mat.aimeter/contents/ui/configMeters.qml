import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "logic.js" as Logic

KCM.SimpleKCM {
    id: page

    property string cfg_metersJson: "[]"
    property var meters: []
    property var profiles: []

    readonly property var typeOptions: ["claude", "codex", "grok", "cursor"]
    property string addType: "claude"

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    readonly property string collectorPath:
        String(Qt.resolvedUrl("../collector/ai-meter")).replace("file://", "")

    // The dialog re-injects stale cfg_* values, so meters load from the collector's config file (the source of truth).
    property bool loaded: false
    property string loadError: ""

    // Called by the dialog right before it copies cfg_* into the applet config (OK saves unconditionally).
    function saveConfig() {
        page.cfg_metersJson = page.loaded ? JSON.stringify(page.meters) : Plasmoid.configuration.metersJson
    }

    Component.onCompleted: {
        configLoader.connectSource("bash " + page.shq(page.collectorPath) + " config get")
        profileLister.connectSource("bash " + page.shq(page.collectorPath) + " profiles")
    }

    onMetersChanged: {
        if (!page.loaded) return
        var s = JSON.stringify(page.meters)
        if (s !== page.cfg_metersJson) page.cfg_metersJson = s
    }

    Plasma5Support.DataSource {
        id: configLoader
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            configLoader.disconnectSource(source)
            var list = null
            try { list = JSON.parse(String(data.stdout || "")).meters } catch (e) { list = null }
            // No fallback to cfg_*: a stale copy saved over config.json would lose hand edits.
            if (!Array.isArray(list)) {
                page.loadError = String(data.stderr || data.stdout || "no output").trim()
                return
            }
            page.meters = list
            page.loaded = true
        }
    }

    function updateMeter(id, patch) {
        page.meters = page.meters.map(function (m) {
            if (m.id !== id) return m
            var out = {}
            for (var k in m) out[k] = m[k]
            for (var pk in patch) out[pk] = patch[pk]
            return out
        })
    }

    function updateOpt(id, key, value) {
        var m = page.meters.find(function (x) { return x.id === id })
        if (!m) return
        var opts = {}
        for (var k in (m.opts || {})) opts[k] = m.opts[k]
        opts[key] = value
        page.updateMeter(id, { opts: opts })
    }

    function toggleHide(id, barKey, hidden) {
        var m = page.meters.find(function (x) { return x.id === id })
        if (!m) return
        var hide = (m.hide || []).slice()
        var idx = hide.indexOf(barKey)
        if (hidden && idx === -1) hide.push(barKey)
        if (!hidden && idx !== -1) hide.splice(idx, 1)
        page.updateMeter(id, { hide: hide })
    }

    Plasma5Support.DataSource {
        id: profileLister
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            profileLister.disconnectSource(source)
            try { page.profiles = JSON.parse(String(data.stdout || "[]")) } catch (e) { page.profiles = [] }
        }
    }

    FileDialog {
        id: iconDialog
        property string targetId: ""
        title: i18n("Choose an icon")
        nameFilters: [i18n("Images (*.svg *.svgz *.png)"), i18n("All files (*)")]
        onAccepted: page.updateMeter(targetId, { icon: String(selectedFile).replace(/^file:\/\//, "") })
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.loadError !== ""
            type: Kirigami.MessageType.Error
            text: i18n("Could not read the AI Meter config, so editing is disabled to protect it: %1", page.loadError)
        }

        RowLayout {
            enabled: page.loaded
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.ComboBox {
                id: typeBox
                model: page.typeOptions.map(function (t) { return Logic.typeLabel(t) })
                onActivated: page.addType = page.typeOptions[currentIndex]
            }
            QQC2.Button {
                text: i18n("Add subscription")
                icon.name: "list-add"
                onClicked: page.meters = Logic.addMeter(page.meters, page.addType)
            }
            Item { Layout.fillWidth: true }
        }

        Repeater {
            model: page.meters
            delegate: Kirigami.AbstractCard {
                id: card
                required property var modelData
                required property int index
                Layout.fillWidth: true

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        Kirigami.Icon {
                            source: card.modelData.icon || Qt.resolvedUrl("../icons/" + card.modelData.type + ".svg")
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        }
                        QQC2.Label {
                            text: Logic.typeLabel(card.modelData.type) + " · " + card.modelData.id
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        QQC2.ToolButton {
                            icon.name: "arrow-up"
                            enabled: card.index > 0
                            onClicked: page.meters = Logic.moveMeter(page.meters, card.modelData.id, "up")
                        }
                        QQC2.ToolButton {
                            icon.name: "arrow-down"
                            enabled: card.index < page.meters.length - 1
                            onClicked: page.meters = Logic.moveMeter(page.meters, card.modelData.id, "down")
                        }
                        QQC2.ToolButton {
                            icon.name: "list-remove"
                            onClicked: page.meters = Logic.removeMeter(page.meters, card.modelData.id)
                        }
                    }

                    Kirigami.FormLayout {
                        Layout.fillWidth: true

                        QQC2.TextField {
                            Kirigami.FormData.label: i18n("Label:")
                            Layout.fillWidth: true
                            text: card.modelData.label
                            onEditingFinished: page.updateMeter(card.modelData.id, { label: text })
                        }
                        QQC2.TextField {
                            Kirigami.FormData.label: i18n("Sub (account name):")
                            Layout.fillWidth: true
                            placeholderText: i18n("e.g. Personal, Work")
                            text: card.modelData.sub || ""
                            onEditingFinished: page.updateMeter(card.modelData.id, { sub: text })
                        }

                        QQC2.CheckBox {
                            Kirigami.FormData.label: i18n("Panel:")
                            text: i18n("Show in panel")
                            checked: card.modelData.panel === true
                            onToggled: page.updateMeter(card.modelData.id, { panel: checked })
                        }
                        QQC2.CheckBox {
                            text: i18n("Send to phone")
                            checked: card.modelData.phone === true
                            onToggled: page.updateMeter(card.modelData.id, { phone: checked })
                        }

                        Item { Kirigami.FormData.isSection: true }

                        Repeater {
                            model: Logic.barKeysFor(card.modelData.type)
                            delegate: QQC2.CheckBox {
                                required property var modelData
                                Kirigami.FormData.label: modelData.k === Logic.barKeysFor(card.modelData.type)[0].k
                                    ? i18n("Bars:") : ""
                                text: modelData.label
                                checked: (card.modelData.hide || []).indexOf(modelData.k) === -1
                                onToggled: page.toggleHide(card.modelData.id, modelData.k, !checked)
                            }
                        }

                        Item { Kirigami.FormData.isSection: true }

                        RowLayout {
                            Kirigami.FormData.label: i18n("Icon:")
                            Layout.fillWidth: true
                            QQC2.Label {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                opacity: card.modelData.icon ? 1 : 0.7
                                text: card.modelData.icon || i18n("Default")
                            }
                            QQC2.Button {
                                icon.name: "document-open"
                                text: i18n("Choose…")
                                onClicked: { iconDialog.targetId = card.modelData.id; iconDialog.open() }
                            }
                            QQC2.Button {
                                icon.name: "edit-clear"
                                text: i18n("Reset")
                                enabled: !!card.modelData.icon
                                onClicked: page.updateMeter(card.modelData.id, { icon: "" })
                            }
                        }

                        Loader {
                            Layout.fillWidth: true
                            sourceComponent: card.modelData.type === "claude" ? claudeOpts
                                : card.modelData.type === "codex" ? codexOpts
                                : card.modelData.type === "grok" ? grokOpts : null
                            onLoaded: item.meterId = card.modelData.id
                        }
                    }
                }
            }
        }

        QQC2.Label {
            visible: page.loaded && page.meters.length === 0
            Layout.fillWidth: true
            opacity: 0.7
            text: i18n("No subscriptions yet. Add one above.")
        }
    }

    Component {
        id: claudeOpts
        Kirigami.FormLayout {
            id: opt
            property string meterId: ""
            property var currentOpts: {
                var m = page.meters.find(function (x) { return x.id === meterId })
                return (m && m.opts) || {}
            }
            onMeterIdChanged: profileBox.sync()
            Layout.fillWidth: true

            // Profiles arrive async; a model reset drops the selection back to "Automatic".
            Connections {
                target: page
                function onProfilesChanged() { profileBox.sync() }
            }

            QQC2.ComboBox {
                id: profileBox
                Kirigami.FormData.label: i18n("Chrome profile:")
                Layout.fillWidth: true
                model: [i18n("Automatic")].concat(page.profiles.map(function (p) { return p.label }))
                    .concat([i18n("Custom path…")])
                property bool syncing: false
                function sync() {
                    syncing = true
                    var cp = opt.currentOpts.cookiesPath || ""
                    var idx = 0
                    if (cp !== "") {
                        idx = page.profiles.length + 1
                        for (var i = 0; i < page.profiles.length; i++)
                            if (page.profiles[i].path === cp) { idx = i + 1; break }
                    }
                    currentIndex = idx
                    syncing = false
                }
                Component.onCompleted: sync()
                onActivated: function (index) {
                    if (syncing) return
                    if (index === 0) page.updateOpt(opt.meterId, "cookiesPath", "")
                    else if (index <= page.profiles.length) page.updateOpt(opt.meterId, "cookiesPath", page.profiles[index - 1].path)
                }
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Cookie database:")
                Layout.fillWidth: true
                visible: profileBox.currentIndex === page.profiles.length + 1
                text: opt.currentOpts.cookiesPath || ""
                placeholderText: i18n("/path/to/Profile/Cookies")
                onEditingFinished: page.updateOpt(opt.meterId, "cookiesPath", text)
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Claude Code directory:")
                Layout.fillWidth: true
                placeholderText: "~/.claude"
                text: opt.currentOpts.claudeDir || ""
                onEditingFinished: page.updateOpt(opt.meterId, "claudeDir", text)
            }
        }
    }

    Component {
        id: codexOpts
        Kirigami.FormLayout {
            id: opt
            property string meterId: ""
            property var currentOpts: {
                var m = page.meters.find(function (x) { return x.id === meterId })
                return (m && m.opts) || {}
            }
            Layout.fillWidth: true
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Codex home:")
                Layout.fillWidth: true
                placeholderText: "~/.codex"
                text: opt.currentOpts.codexHome || ""
                onEditingFinished: page.updateOpt(opt.meterId, "codexHome", text)
            }
        }
    }

    Component {
        id: grokOpts
        Kirigami.FormLayout {
            id: opt
            property string meterId: ""
            property var currentOpts: {
                var m = page.meters.find(function (x) { return x.id === meterId })
                return (m && m.opts) || {}
            }
            Layout.fillWidth: true
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Grok home:")
                Layout.fillWidth: true
                placeholderText: "~/.grok"
                text: opt.currentOpts.grokHome || ""
                onEditingFinished: page.updateOpt(opt.meterId, "grokHome", text)
            }
        }
    }
}
