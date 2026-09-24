import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "logic.js" as Logic

PlasmoidItem {
    id: root

    property var meters: []
    property int snapshotTs: 0
    property bool haveSnapshot: false
    property bool snapshotError: false
    property string snapshotErrorText: ""
    property int now: Math.floor(Date.now() / 1000)
    property bool syncingConfig: false

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    readonly property string collectorPath:
        String(Qt.resolvedUrl("../collector/ai-meter")).replace("file://", "")
    readonly property string collectorCmd: "bash " + shq(collectorPath)

    readonly property var pinnedMeters: meters.filter(function (m) { return m.panel === true })
    readonly property bool showAppIcon: Plasmoid.configuration.showAppIcon || pinnedMeters.length === 0
    readonly property int panelBars: Plasmoid.configuration.panelBars

    // No preferredRepresentation override: default picks compact for a panel, full elsewhere.
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    toolTipMainText: "AI Meter"
    toolTipSubText: root.tooltipText()

    function tooltipText() {
        if (root.snapshotError) return root.snapshotErrorText || "Collector error"
        if (!root.haveSnapshot || root.meters.length === 0) return "No subscriptions configured"
        var lines = []
        for (var i = 0; i < root.meters.length; i++) {
            var m = root.meters[i]
            var top = (m.bars && m.bars.length > 0) ? m.bars[0] : null
            var line = m.label + (m.sub ? " · " + m.sub : "")
            if (top) line += "  " + (top.pct === null ? "—" : Math.round(top.pct) + "%") + " " + top.label
            else line += "  " + Logic.statusText(m)
            lines.push(line)
        }
        return lines.join("\n")
    }

    function appIconColor() {
        if (root.snapshotError) return Qt.rgba(0.85, 0.35, 0.3, 1)
        var bucket = Logic.worstBucket(root.meters, root.now)
        if (bucket === "red") return Qt.hsla(0, 0.72, 0.55, 1)
        if (bucket === "yellow") return Qt.hsla(55 / 360, 0.72, 0.55, 1)
        return Kirigami.Theme.textColor
    }

    function iconForMeter(m) {
        if (m.icon && m.icon !== "") return m.icon
        return Qt.resolvedUrl("../icons/" + m.type + ".svg")
    }

    // ---- snapshot polling ----

    Plasma5Support.DataSource {
        id: execSnapshot
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            execSnapshot.disconnectSource(source)
            root.applySnapshot(data && data.stdout ? String(data.stdout) : "")
        }
        function poll() {
            var maxAge = Math.max(5, Plasmoid.configuration.refreshSec - 5)
            execSnapshot.connectSource(root.collectorCmd + " snapshot --max-age " + maxAge)
        }
    }

    Plasma5Support.DataSource {
        id: execCollect
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            execCollect.disconnectSource(source)
            root.applySnapshot(data && data.stdout ? String(data.stdout) : "")
        }
        function run() { execCollect.connectSource(root.collectorCmd + " collect") }
    }

    function applySnapshot(out) {
        out = out.trim()
        if (out.length === 0) {
            root.snapshotError = true
            root.snapshotErrorText = "Collector produced no output. Is it installed at contents/collector/ai-meter?"
            return
        }
        try {
            var j = JSON.parse(out)
            root.meters = j.meters || []
            root.snapshotTs = j.ts || Math.floor(Date.now() / 1000)
            root.haveSnapshot = true
            root.snapshotError = false
            root.snapshotErrorText = ""
        } catch (e) {
            root.snapshotError = true
            root.snapshotErrorText = "Collector returned invalid JSON: " + e
        }
    }

    // ---- config sync (config.json file is the source of truth) ----

    Plasma5Support.DataSource {
        id: execConfigGet
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            execConfigGet.disconnectSource(source)
            var out = data && data.stdout ? String(data.stdout).trim() : ""
            if (out.length === 0) return
            try {
                var cfg = JSON.parse(out)
                var fileMeters = JSON.stringify(cfg.meters || [])
                if (fileMeters !== Plasmoid.configuration.metersJson) {
                    root.syncingConfig = true
                    Plasmoid.configuration.metersJson = fileMeters
                    root.syncingConfig = false
                }
            } catch (e) { /* leave local config untouched on bad JSON */ }
            execSnapshot.poll()
        }
        function run() { execConfigGet.connectSource(root.collectorCmd + " config get") }
    }

    Plasma5Support.DataSource {
        id: execConfigSet
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            execConfigSet.disconnectSource(source)
            execCollect.run()
        }
        function run(b64) { execConfigSet.connectSource(root.collectorCmd + " config set --b64 " + b64) }
    }

    function pushConfig() {
        var payload = { v: 1, meters: JSON.parse(Plasmoid.configuration.metersJson || "[]") }
        var b64 = Logic.utf8ToBase64(JSON.stringify(payload))
        execConfigSet.run(b64)
    }

    Connections {
        target: Plasmoid.configuration
        function onMetersJsonChanged() {
            if (root.syncingConfig) return
            root.pushConfig()
        }
    }

    Timer {
        interval: Math.max(30, Plasmoid.configuration.refreshSec) * 1000
        running: true
        repeat: true
        onTriggered: execSnapshot.poll()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Math.floor(Date.now() / 1000)
    }

    Component.onCompleted: execConfigGet.run()

    // ---- reusable bar ----

    component MeterBar : Item {
        id: mb
        property string label: ""
        property var pct: null
        property var resetAt: null
        property int win: 0
        property bool fresh: false
        property bool ok: true
        property bool showValue: true
        property real labelWidth: -1
        readonly property real labelImplicitWidth: labelItem.visible ? labelItem.implicitWidth : 0

        implicitHeight: Kirigami.Units.gridUnit
        implicitWidth: Kirigami.Units.gridUnit * 6

        readonly property real v: pct === null ? 0 : Math.max(0, Math.min(100, pct))
        readonly property var timePct: mb.ok ? Logic.timePctOf(mb.resetAt, root.now, mb.win) : null
        readonly property color fillColor: !mb.ok
            ? Qt.rgba(0.56, 0.58, 0.63, 1.0)
            : Logic.paceColor(mb.v, mb.timePct)

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                id: labelItem
                text: mb.label
                visible: mb.label.length > 0
                font.pixelSize: Math.max(8, mb.height * 0.62)
                font.bold: true
                opacity: 0.6
                Layout.minimumHeight: 0
                Layout.fillHeight: true
                Layout.preferredWidth: mb.label.length === 0 ? 0
                    : mb.labelWidth >= 0 ? mb.labelWidth : Kirigami.Units.gridUnit * 0.95
                verticalAlignment: Text.AlignVCenter
            }

            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.maximumHeight: Kirigami.Units.gridUnit * 0.9
                Layout.alignment: Qt.AlignVCenter
                radius: height / 2
                color: Qt.rgba(0.5, 0.5, 0.56, 0.28)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Rectangle {
                    height: parent.height
                    width: (!mb.ok || mb.pct === null || mb.v <= 0) ? 0 : parent.width * mb.v / 100.0
                    topLeftRadius: height / 2
                    bottomLeftRadius: height / 2
                    topRightRadius: Math.max(0, Math.min(height / 2, width - (parent.width - height / 2)))
                    bottomRightRadius: topRightRadius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.lighter(mb.fillColor, 1.35) }
                        GradientStop { position: 1.0; color: mb.fillColor }
                    }
                    Behavior on width { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    visible: mb.ok && mb.timePct !== null
                    width: 2
                    height: parent.height + 4
                    y: -2
                    x: Math.max(0, Math.min(parent.width - width,
                                parent.width * Math.min(100, (mb.timePct || 0)) / 100.0 - width / 2))
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.92)
                    Behavior on x { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }
                }

                PlasmaComponents.Label {
                    visible: mb.fresh && mb.ok
                    text: "unused"
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Math.max(7, parent.height * 0.62)
                    opacity: 0.75
                }
            }

            PlasmaComponents.Label {
                visible: mb.showValue
                text: (mb.ok && mb.pct !== null) ? Math.round(mb.v) + "%" : "—"
                font.pixelSize: Math.max(8, mb.height * 0.58)
                font.bold: true
                color: mb.ok ? mb.fillColor : Qt.rgba(0.6, 0.6, 0.6, 1)
                Layout.minimumHeight: 0
                Layout.fillHeight: true
                Layout.preferredWidth: mb.showValue ? Kirigami.Units.gridUnit * 1.7 : 0
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    // ---- compact (panel) ----

    compactRepresentation: MouseArea {
        id: compactRoot
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Layout.minimumWidth: contentRow.implicitWidth
        Layout.preferredWidth: contentRow.implicitWidth
        Layout.minimumHeight: Kirigami.Units.gridUnit * 1.6

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            height: parent.height - Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing * 0.6

            Kirigami.Icon {
                visible: root.showAppIcon
                source: Qt.resolvedUrl("../icons/aimeter.svg")
                isMask: Plasmoid.configuration.monochromeIcon
                color: root.appIconColor()
                Layout.preferredWidth: Math.round(contentRow.height * 0.72)
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignVCenter

                Kirigami.Icon {
                    visible: root.snapshotError
                    source: "data-warning"
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: parent.width * 0.55
                    height: width
                }
            }

            Repeater {
                model: root.pinnedMeters
                delegate: RowLayout {
                    id: meterRow
                    required property var modelData
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillHeight: true

                    Kirigami.Icon {
                        source: root.iconForMeter(meterRow.modelData)
                        isMask: Plasmoid.configuration.monochromeIcon
                        color: Kirigami.Theme.textColor
                        Layout.preferredWidth: Math.round(contentRow.height * 0.6)
                        Layout.preferredHeight: Layout.preferredWidth
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        id: barsCol
                        // Widest bar label in this meter, so "Models"/"Other" don't collide with the bar.
                        property real maxLabel: 0
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5 + maxLabel
                        Layout.fillHeight: true
                        spacing: 2

                        Repeater {
                            model: (meterRow.modelData.bars || []).slice(0, root.panelBars)
                            delegate: MeterBar {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                labelWidth: barsCol.maxLabel
                                onLabelImplicitWidthChanged: barsCol.maxLabel = Math.max(barsCol.maxLabel, labelImplicitWidth)
                                label: Plasmoid.configuration.showWindowLabels ? modelData.label : ""
                                pct: modelData.pct
                                resetAt: modelData.reset_at
                                win: modelData.win
                                fresh: modelData.fresh === true
                                ok: meterRow.modelData.ok !== false
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- full (popup) ----

    component MeterSection : ColumnLayout {
        id: section
        property var meter: null
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: root.iconForMeter(section.meter)
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                spacing: 0
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents.Label {
                        text: section.meter.label
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 1.0
                    }
                    PlasmaComponents.Label {
                        visible: section.meter.plan
                        text: section.meter.plan || ""
                        opacity: 0.7
                        font.pixelSize: Kirigami.Units.gridUnit * 0.72
                    }
                }
                PlasmaComponents.Label {
                    visible: !!section.meter.sub
                    text: section.meter.sub || ""
                    opacity: 0.6
                    font.pixelSize: Kirigami.Units.gridUnit * 0.72
                }
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents.Label {
                text: Logic.statusText(section.meter)
                color: Logic.statusWarn(section.meter) ? Qt.rgba(0.9, 0.55, 0.2, 1) : Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Units.gridUnit * 0.72
            }
        }

        Repeater {
            model: section.meter.bars || []
            delegate: ColumnLayout {
                id: barBlock
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents.Label {
                        text: barBlock.modelData.label
                        opacity: 0.8
                        font.pixelSize: Kirigami.Units.gridUnit * 0.82
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        opacity: 0.55
                        font.pixelSize: Kirigami.Units.gridUnit * 0.72
                        text: barBlock.modelData.fresh
                            ? "unused"
                            : Logic.resetText(barBlock.modelData.reset_at, root.now)
                    }
                    PlasmaComponents.Label {
                        text: barBlock.modelData.pct === null ? "—" : Math.round(barBlock.modelData.pct) + "%"
                        font.bold: true
                        font.pixelSize: Kirigami.Units.gridUnit * 0.9
                    }
                }

                MeterBar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.05
                    showValue: false
                    ok: section.meter.ok !== false
                    pct: barBlock.modelData.pct
                    resetAt: barBlock.modelData.reset_at
                    win: barBlock.modelData.win
                    fresh: barBlock.modelData.fresh === true
                }
            }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        // Minimum tracks the content (capped) so a remembered small popup size can't force scrolling.
        Layout.minimumHeight: Math.min(Kirigami.Units.gridUnit * 56,
            Math.max(Kirigami.Units.gridUnit * 16, sectionsCol.implicitHeight + Kirigami.Units.gridUnit * 6))
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Layout.minimumHeight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: Qt.resolvedUrl("../icons/aimeter.svg")
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                PlasmaComponents.Label {
                    text: "AI Meter"
                    font.bold: true
                    font.pixelSize: Kirigami.Units.gridUnit * 1.1
                }
                Item { Layout.fillWidth: true }
            }

            PlasmaComponents.Label {
                visible: root.snapshotError
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Qt.rgba(0.9, 0.4, 0.35, 1)
                text: root.snapshotErrorText
            }

            PlasmaComponents.Label {
                visible: !root.snapshotError && root.meters.length === 0
                Layout.fillWidth: true
                opacity: 0.7
                wrapMode: Text.WordWrap
                text: "No subscriptions configured yet. Open settings to add one."
            }

            QQC2.ScrollView {
                visible: root.meters.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth

                ColumnLayout {
                    id: sectionsCol
                    // Keep bar ends clear of the scrollbar.
                    width: parent.width - Kirigami.Units.gridUnit
                    spacing: Kirigami.Units.largeSpacing

                    Repeater {
                        model: root.meters
                        delegate: MeterSection {
                            required property var modelData
                            Layout.fillWidth: true
                            meter: modelData
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    text: Logic.updatedText(root.snapshotTs, root.now)
                    opacity: 0.55
                    font.pixelSize: Kirigami.Units.gridUnit * 0.72
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Button {
                    text: "Refresh"
                    icon.name: "view-refresh"
                    onClicked: execCollect.run()
                }
                PlasmaComponents.Button {
                    text: "Settings…"
                    icon.name: "configure"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }
        }
    }
}
