import QtQuick
import Quickshell
import "../theme"

// ── AudioPopup ────────────────────────────────────────────────────────────────
// Shows volume/mic sliders and, when more than one device exists, device pickers
// for sinks and sources.  Uses PopupBase for the shared open/close animation.
PopupBase {
    id: root

    implicitWidth:  300
    borderColor:    PanelColors.audio
    clipContent:    false    // tooltip must be able to overflow the panel bounds
    contentHeight:  popupColumn.implicitHeight

    // Drive the shared open/close animation from AudioState.popupVisible.
    // Must be a Connections (not a Binding) because PopupBase's closing transition
    // ends by writing animState = "closed" via a ScriptAction.  A Binding would
    // immediately override that back to "closing" and create an infinite loop.
    Connections {
        target: AudioState
        function onPopupVisibleChanged() {
            root.animState = AudioState.popupVisible ? "open" : "closing"
        }
    }

    // ── Tooltip state ─────────────────────────────────────────────────────────
    property string _tipText: ""
    property point  _tipPos:  Qt.point(0, 0)

    Timer {
        id: _tipShowTimer
        interval: 400
        onTriggered: _tipShowAnim.start()
    }
    NumberAnimation { id: _tipShowAnim; target: tooltip; property: "opacity"; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { id: _tipHideAnim; target: tooltip; property: "opacity"; to: 0.0; duration: 120; easing.type: Easing.InCubic }

    function _showTip(item, text) {
        _tipShowTimer.stop()
        _tipShowAnim.stop()
        _tipHideAnim.stop()
        tooltip.opacity = 0
        root._tipText = text
        // Map the item's top-left into the popup's coordinate space
        const mapped = item.mapToItem(root, 0, 0)
        root._tipPos  = Qt.point(14, mapped.y - tooltip.height - 6)
        _tipShowTimer.start()
    }

    function _hideTip() {
        _tipShowTimer.stop()
        _tipShowAnim.stop()
        _tipHideAnim.start()
    }

    // ── Device name prettifier ────────────────────────────────────────────────
    // Strips common boilerplate words and de-duplicates tokens.
    function _shortName(desc) {
        if (!desc) return ""
        const noise = /\b(HD Audio|Controller|Analog|Stereo|Mono|Digital|Output|Input|Series)\b/gi
        let words = desc.trim().replace(noise, "").split(/\s+/).filter(w => w.length > 0)
        const seen = new Set()
        const unique = []
        for (const w of words) {
            const lw = w.toLowerCase()
            if (!seen.has(lw)) { seen.add(lw); unique.push(w) }
        }
        return unique.join(" ").replace(/[()[\]\-_]/g, " ").replace(/\s{2,}/g, " ").trim() || desc
    }

    // ── Shared: Icon toggle button ────────────────────────────────────────────
    // active=true  (unmuted): accent bg  + dark icon
    // active=false (muted):   track bg   + accent icon
    component IconButton: Rectangle {
        id: btn
        property string icon:   ""
        property bool   active: true
        signal clicked()

        width:  height    // always square; caller binds height to its sibling slider
        radius: 6
        color:  btn.active ? PanelColors.audio : PanelColors.trackBackground
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors.centerIn: parent
            text:             btn.icon
            font.pixelSize:   16
            font.family:      "JetBrainsMono Nerd Font"
            color:            btn.active ? PanelColors.pillForeground : PanelColors.audio
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape:  Qt.PointingHandCursor
            onClicked:    btn.clicked()
        }
    }

    // ── Shared: Device-picker row delegate ────────────────────────────────────
    // Used for both sink and source repeaters to avoid duplicated markup.
    component DeviceRow: Rectangle {
        id: devRow

        // Required data from the Repeater
        required property var    modelData
        // Whether this device is the currently active default
        property bool isActive:  false
        // Signal emitted when the user picks this device
        signal selected(string name)

        // parent is the Column (popupColumn) when used as a Repeater delegate
        width:  parent.width
        height: 34
        radius: 6
        color: {
            const base = isActive ? PanelColors.audio : PanelColors.rowBackground
            return (devHover.containsMouse && !isActive) ? Qt.lighter(base, 1.15) : base
        }
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
            anchors {
                left:            parent.left
                verticalCenter:  parent.verticalCenter
                leftMargin:      14
                right:           parent.right
                rightMargin:     8
            }
            text:               root._shortName(devRow.modelData.description)
            font.pixelSize:     13
            font.bold:          true
            font.family:        "JetBrainsMono Nerd Font"
            color:              devRow.isActive ? PanelColors.pillForeground : PanelColors.textMain
            elide:              Text.ElideRight
        }

        MouseArea {
            id:           devHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onEntered:    root._showTip(devRow, devRow.modelData.description)
            onExited:     root._hideTip()
            onClicked:    devRow.selected(devRow.modelData.name)
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    Column {
        id: popupColumn
        anchors {
            top:     parent.top
            left:    parent.left
            right:   parent.right
            margins: root.padding
        }
        spacing: 8

        // ── Output section header (only shown when >1 sink) ───────────────────
        Row {
            visible:      AudioState.sinks.length > 1
            height:       visible ? implicitHeight : 0
            spacing:      6
            leftPadding:  4
            bottomPadding: 2

            Text { text: "󰕾"; font.pixelSize: 16; font.family: "JetBrainsMono Nerd Font"; color: PanelColors.audio; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Output"; font.pixelSize: 14; font.bold: true; font.family: "JetBrainsMono Nerd Font"; color: PanelColors.textMain; anchors.verticalCenter: parent.verticalCenter }
        }

        Repeater {
            model: AudioState.sinks.length > 1 ? AudioState.sinks : []
            DeviceRow {
                isActive: modelData.name === AudioState.defaultSink
                onSelected: (name) => AudioState.setDefaultSink(name)
            }
        }

        // ── Input section header (only shown when >1 source) ─────────────────
        Row {
            visible:      AudioState.sources.length > 1
            height:       visible ? implicitHeight : 0
            spacing:      6
            leftPadding:  4
            topPadding:   AudioState.sinks.length > 1 ? 4 : 0
            bottomPadding: 2

            Text { text: "󰍬"; font.pixelSize: 16; font.family: "JetBrainsMono Nerd Font"; color: PanelColors.audio; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "Input"; font.pixelSize: 14; font.bold: true; font.family: "JetBrainsMono Nerd Font"; color: PanelColors.textMain; anchors.verticalCenter: parent.verticalCenter }
        }

        Repeater {
            model: AudioState.sources.length > 1 ? AudioState.sources : []
            DeviceRow {
                isActive: modelData.name === AudioState.defaultSource
                onSelected: (name) => AudioState.setDefaultSource(name)
            }
        }

        // ── Divider (only when device pickers are visible) ────────────────────
        Rectangle {
            visible: AudioState.sinks.length > 1 || AudioState.sources.length > 1
            width:   parent.width
            height:  visible ? 1 : 0
            color:   PanelColors.border
        }

        // ── Volume row ────────────────────────────────────────────────────────
        Row {
            width:   popupColumn.width
            height:  34
            spacing: 6

            IconButton {
                height:               volSlider.height
                active:               !AudioState.muted
                icon:                 AudioState.muted ? "󰝟" : "󰕾"
                anchors.verticalCenter: parent.verticalCenter
                onClicked:            AudioState.setMute(!AudioState.muted)
            }

            PanelSlider {
                id:           volSlider
                // Width fills row minus the square icon button and spacing
                width:        parent.width - height - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                clickable:    true
                label:        AudioState.volume + "%"
                value:        AudioState.volume
                accentColor:  AudioState.muted ? PanelColors.textDim : PanelColors.audio
                onMoved:      (v) => AudioState.setVolume(v)
            }
        }

        // ── Mic row ───────────────────────────────────────────────────────────
        Row {
            width:   popupColumn.width
            height:  34
            spacing: 6

            IconButton {
                height:               micSlider.height
                active:               !AudioState.micMuted
                icon:                 AudioState.micMuted ? "󰍭" : "󰍬"
                anchors.verticalCenter: parent.verticalCenter
                onClicked:            AudioState.setMicMute(!AudioState.micMuted)
            }

            PanelSlider {
                id:           micSlider
                width:        parent.width - height - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                clickable:    true
                label:        AudioState.micVolume + "%"
                value:        AudioState.micVolume
                accentColor:  AudioState.micMuted ? PanelColors.textDim : PanelColors.audio
                onMoved:      (v) => AudioState.setMicVolume(v)
            }
        }
    }

    // ── Tooltip overlay ───────────────────────────────────────────────────────
    // Rendered above all other children (high z-order).
    // pointer-events are disabled so it never blocks mouse input.
    Rectangle {
        id:      tooltip
        opacity: 0
        z:       9999
        enabled: false    // transparent to input

        width:  tipLabel.implicitWidth + 16
        height: 26
        radius: 6
        color:  PanelColors.rowBackground
        border { color: PanelColors.audio; width: 1 }

        x: root._tipPos.x
        y: root._tipPos.y

        Behavior on opacity { NumberAnimation { duration: 100 } }

        Text {
            id:              tipLabel
            anchors.centerIn: parent
            text:            root._tipText
            font.pixelSize:  11
            font.family:     "JetBrainsMono Nerd Font"
            color:           PanelColors.textMain
        }
    }
}
