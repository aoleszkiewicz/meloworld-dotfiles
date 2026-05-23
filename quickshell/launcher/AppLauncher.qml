import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../theme"
import "../dock"

PanelWindow {
    id: root

    anchors.top:    true
    anchors.bottom: true
    anchors.left:   true
    anchors.right:  true
    exclusiveZone:  0

    WlrLayershell.layer:         WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    color:   "transparent"
    visible: animState !== "closed"

    mask: Region { item: panel }

    // ── Panel animation state ─────────────────────────────────────────────
    property string animState:     "closed"
    property int    selectedIndex: 0

    // ── Pagination & View Mode ────────────────────────────────────────────
    property bool isGridView: false
    property int totalPages:  1
    property int currentPage: 0
    readonly property int itemsPerPage: isGridView ? 15 : 7

    // Ordered list of original indices for all currently matched apps
    property var filteredApps: []

    Shortcut {
        sequence: "Ctrl+G"
        onActivated: {
            root.isGridView = !root.isGridView
            filterTimer.restart()
        }
    }

    // ── Hidden-apps popup (right-click empty space) ───────────────────────
    property bool _hiddenMenuOpen: false

    Timer {
        id: hiddenDismissTimer
        interval: 3000
        running:  root._hiddenMenuOpen
        onTriggered: root._closeHiddenMenu()
    }

    function _openHiddenMenu() {
        if (_hiddenMenuOpen) { _closeHiddenMenu(); return }
        _hiddenMenuOpen         = true
        hiddenMenuInner.y       = 14
        hiddenMenuInner.opacity = 0.0
        hiddenMenuPopup.visible = true
        hiddenOpenAnim.restart()
        hiddenDismissTimer.restart()
    }

    function _closeHiddenMenu() {
        if (!_hiddenMenuOpen) return
        _hiddenMenuOpen = false
        hiddenOpenAnim.stop()
        hiddenCloseAnim.restart()
    }

    // ── Filter ────────────────────────────────────────────────────────────
    Timer {
        id: filterTimer
        interval: 10
        onTriggered: root.updateFilter()
    }

    function updateFilter() {
        var firstMatch = -1

        var items = []
        var q = searchInput.text.toLowerCase()

        for (var i = 0; i < appsRepeater.count; i++) {
            var item = appsRepeater.itemAt(i)
            if (!item) continue

            var hidden = LauncherHiddenApps.isHidden(item.appId)
            
            var nameMatch = q === "" ||
                            item.appName.toLowerCase().includes(q) ||
                            (item.appData && item.appData.genericName && String(item.appData.genericName).toLowerCase().includes(q)) ||
                            (item.appData && item.appData.comment && String(item.appData.comment).toLowerCase().includes(q)) ||
                            (item.appData && item.appData.keywords && String(item.appData.keywords).toLowerCase().includes(q))

            var isMatch = !hidden && nameMatch
            item.isMatch = isMatch

            if (isMatch) {
                items.push({
                    item: item,
                    origIndex: i,
                    usage: AppUsageTracker.getUsage(item.appId),
                    name: item.appName.toLowerCase()
                })
            } else {
                item.filteredIndex = -1
            }
        }

        // Sort items: Usage (descending), then Name (ascending)
        items.sort(function(a, b) {
            if (b.usage !== a.usage) {
                return b.usage - a.usage
            }
            return a.name.localeCompare(b.name)
        })

        // Assign filteredIndex based on sorted order
        var mapped = []
        for (var j = 0; j < items.length; j++) {
            items[j].item.filteredIndex = j
            mapped.push(items[j].origIndex)
            if (firstMatch === -1) firstMatch = items[j].origIndex
        }
        root.filteredApps = mapped

        root.totalPages = Math.max(1, Math.ceil(items.length / root.itemsPerPage))
        if (root.currentPage >= root.totalPages)
            root.currentPage = Math.max(0, root.totalPages - 1)
        root.selectedIndex = firstMatch
    }

    // ── Connections ───────────────────────────────────────────────────────
    Connections {
        target: LauncherState
        function onVisibleChanged() {
            root.animState = LauncherState.visible ? "open" : "closing"
            if (LauncherState.visible) {
                searchInput.text = ""
                root.currentPage = 0
                root._closeHiddenMenu()
                filterTimer.restart()
            } else {
                root._closeHiddenMenu()
            }
        }
    }

    Connections {
        target: LauncherHiddenApps
        function onHiddenAppsChanged() { filterTimer.restart() }
    }

    Connections {
        target: AppUsageTracker
        function onUsageMapChanged() { filterTimer.restart() }
    }

    onAnimStateChanged: {
        if (animState === "open") searchInput.forceActiveFocus()
    }

    // ── IPC ───────────────────────────────────────────────────────────────
    IpcHandler {
        target: "launcher"
        function toggle(): void { LauncherState.toggle() }
    }

    // ── Hidden-apps PopupWindow ───────────────────────────────────────────
    // Anchored to the panel top-center, same PopupWindow pattern as the dock.
    PopupWindow {
        id: hiddenMenuPopup

        anchor.item:           panel
        anchor.edges:          Edges.Top
        anchor.gravity:        Edges.Top
        anchor.margins.bottom: 8

        color:          "transparent"
        implicitWidth:  220
        implicitHeight: hiddenMenuInner.implicitHeight

        visible: false

        SequentialAnimation {
            id: hiddenOpenAnim
            ParallelAnimation {
                NumberAnimation {
                    target: hiddenMenuInner; property: "y"
                    to: 0; duration: 220; easing.type: Easing.OutExpo
                }
                NumberAnimation {
                    target: hiddenMenuInner; property: "opacity"
                    to: 1.0; duration: 170; easing.type: Easing.OutCubic
                }
            }
        }

        SequentialAnimation {
            id: hiddenCloseAnim
            ParallelAnimation {
                NumberAnimation {
                    target: hiddenMenuInner; property: "y"
                    to: 14; duration: 160; easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: hiddenMenuInner; property: "opacity"
                    to: 0.0; duration: 130; easing.type: Easing.InCubic
                }
            }
            ScriptAction { script: hiddenMenuPopup.visible = false }
        }

        mask: Region { item: hiddenMenuInner }

        Rectangle {
            id: hiddenMenuInner

            width:          parent.width
            implicitHeight: hiddenMenuCol.implicitHeight + padding * 2
            height:         implicitHeight
            radius:         10
            color:          PanelColors.popupBackground
            border.color:   PanelColors.border
            border.width:   2
            clip:           true

            readonly property int padding: 12

            Behavior on color        { ColorAnimation { duration: PanelColors.transitionDuration } }
            Behavior on border.color { ColorAnimation { duration: PanelColors.transitionDuration } }

            HoverHandler {
                onHoveredChanged: { if (hovered) hiddenDismissTimer.restart() }
            }

            Column {
                id: hiddenMenuCol
                anchors {
                    top:     parent.top
                    left:    parent.left
                    right:   parent.right
                    margins: hiddenMenuInner.padding
                }
                spacing: 4

                Text {
                    width:          parent.width
                    text:           "Hidden Apps"
                    font.pixelSize: 12
                    font.bold:      true
                    font.family:    "JetBrainsMono Nerd Font"
                    color:          PanelColors.textDim
                    bottomPadding:  4
                }

                Rectangle {
                    width:  parent.width
                    height: 2
                    color:  PanelColors.border
                }

                Text {
                    width:          parent.width
                    text:           "No hidden apps"
                    font.pixelSize: 13
                    font.family:    "JetBrainsMono Nerd Font"
                    color:          PanelColors.textDim
                    visible:        LauncherHiddenApps.hiddenApps.length === 0
                    topPadding:     4
                    bottomPadding:  4
                    horizontalAlignment: Text.AlignHCenter
                }

                Repeater {
                    model: LauncherHiddenApps.hiddenApps

                    delegate: Item {
                        required property var modelData
                        width:  hiddenMenuCol.width
                        height: 34

                        Rectangle {
                            anchors.fill: parent
                            radius:       6
                            color: hRow.containsMouse
                                ? Qt.lighter(PanelColors.rowBackground, 1.15)
                                : PanelColors.rowBackground
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Rectangle {
                                width: 3; height: parent.height - 10; radius: 2
                                anchors {
                                    left:           parent.left
                                    leftMargin:     4
                                    verticalCenter: parent.verticalCenter
                                }
                                color: PanelColors.textDim
                            }

                            Text {
                                anchors {
                                    left:           parent.left
                                    leftMargin:     14
                                    right:          parent.right
                                    rightMargin:    10
                                    verticalCenter: parent.verticalCenter
                                }
                                text:           modelData.name
                                font.pixelSize: 13
                                font.bold:      true
                                font.family:    "JetBrainsMono Nerd Font"
                                color:          PanelColors.textMain
                                elide:          Text.ElideRight
                            }

                            MouseArea {
                                id: hRow
                                anchors.fill: parent
                                hoverEnabled: true
                                onContainsMouseChanged: {
                                    if (containsMouse) hiddenDismissTimer.restart()
                                }
                                onClicked: {
                                    LauncherHiddenApps.show(modelData.id)
                                    root._closeHiddenMenu()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: panel

        readonly property int panelWidth: 600

        width:  panelWidth
        height: panelColumn.implicitHeight + 20

        x: Math.round((parent.width  - width)  / 2)
        y: Math.round((parent.height - height) / 2)

        radius:       12
        color:        PanelColors.popupBackground
        Behavior on color { ColorAnimation { duration: PanelColors.transitionDuration } }

        border.color: PanelColors.border
        Behavior on border.color { ColorAnimation { duration: PanelColors.transitionDuration } }
        border.width: 4
        clip:         false

        opacity: 0.0
        transform: Translate { id: panelSlide; y: 28 }

        // ── Focus on hover ──────────────────────────────────────────────
        HoverHandler {
            onHoveredChanged: { if (hovered) panel.forceActiveFocus() }
        }

        states: [
            State {
                name: "open"
                when: root.animState === "open"
                PropertyChanges { target: panel;      opacity: 1.0 }
                PropertyChanges { target: panelSlide; y: 0         }
            },
            State {
                name: "closing"
                when: root.animState === "closing"
                PropertyChanges { target: panel;      opacity: 0.0 }
                PropertyChanges { target: panelSlide; y: 28        }
            }
        ]

        transitions: [
            Transition {
                to: "open"
                SequentialAnimation {
                    PropertyAction { target: panelSlide; property: "y";       value: 28  }
                    PropertyAction { target: panel;      property: "opacity"; value: 0.0 }
                    ParallelAnimation {
                        NumberAnimation {
                            target: panelSlide; property: "y"
                            to: 0; duration: 280; easing.type: Easing.OutExpo
                        }
                        NumberAnimation {
                            target: panel; property: "opacity"
                            to: 1.0; duration: 200; easing.type: Easing.OutCubic
                        }
                    }
                }
            },
            Transition {
                to: "closing"
                SequentialAnimation {
                    ParallelAnimation {
                        NumberAnimation {
                            target: panelSlide; property: "y"
                            to: 28; duration: 180; easing.type: Easing.InCubic
                        }
                        NumberAnimation {
                            target: panel; property: "opacity"
                            to: 0.0; duration: 150; easing.type: Easing.InCubic
                        }
                    }
                    ScriptAction { script: root.animState = "closed" }
                }
            }
        ]

        // ── Right-click on panel chrome or empty grid space ─────────────
        MouseArea {
            anchors.fill:    parent
            z:               0
            acceptedButtons: Qt.RightButton
            onClicked:       root._openHiddenMenu()
        }

        // ── Content ─────────────────────────────────────────────────────
        Column {
            id: panelColumn
            anchors {
                top:     parent.top
                left:    parent.left
                right:   parent.right
                margins: 10
            }
            spacing: 8

            // ── Search bar ───────────────────────────────────────────────
            Rectangle {
                id:     searchBar
                width:  parent.width
                height: 44
                radius: 8
                color:  PanelColors.rowBackground
                Behavior on color { ColorAnimation { duration: PanelColors.transitionDuration } }

                border.color: searchInput.activeFocus ? PanelColors.launcher : "transparent"
                Behavior on border.color { ColorAnimation { duration: 150 } }
                border.width: 0

                Item {
                    anchors {
                        fill:        parent
                        leftMargin:  12
                        rightMargin: 12
                    }

                    Text {
                        anchors.fill:      parent
                        text:              " Search..."
                        font.pixelSize:    13
                        font.bold:         true
                        font.family:       "JetBrainsMono Nerd Font"
                        color:             PanelColors.textDim
                        verticalAlignment: Text.AlignVCenter
                        visible:           searchInput.text === ""
                    }

                    TextInput {
                        id:                searchInput
                        anchors.fill:      parent
                        color:             PanelColors.textMain
                        font.pixelSize:    13
                        font.bold:         true
                        font.family:       "JetBrainsMono Nerd Font"
                        selectByMouse:     true
                        clip:              true
                        verticalAlignment: TextInput.AlignVCenter

                        onTextChanged: filterTimer.restart()

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up || 
                                event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                                
                                if (root.filteredApps.length === 0) return
                                
                                var currentFidx = root.filteredApps.indexOf(root.selectedIndex)
                                if (currentFidx === -1) currentFidx = 0
                                
                                var cols = root.isGridView ? 5 : 1
                                var nextFidx = currentFidx

                                if (event.key === Qt.Key_Down) {
                                    nextFidx = Math.min(currentFidx + cols, root.filteredApps.length - 1)
                                } else if (event.key === Qt.Key_Up) {
                                    nextFidx = Math.max(currentFidx - cols, 0)
                                } else if (event.key === Qt.Key_Tab) {
                                    nextFidx = Math.min(currentFidx + 1, root.filteredApps.length - 1)
                                } else if (event.key === Qt.Key_Backtab) {
                                    nextFidx = Math.max(currentFidx - 1, 0)
                                }
                                
                                if (nextFidx !== currentFidx) {
                                    root.selectedIndex = root.filteredApps[nextFidx]
                                    
                                    // Auto-flip page if selection moves off-screen
                                    var newPage = Math.floor(nextFidx / root.itemsPerPage)
                                    if (newPage !== root.currentPage) {
                                        root.currentPage = newPage
                                    }
                                }
                                event.accepted = true
                            }
                        }

                        Keys.onReturnPressed: {
                            if (root.selectedIndex !== -1) {
                                var item = appsRepeater.itemAt(root.selectedIndex)
                                if (item) item.executeApp()
                            } else if (searchInput.text.trim() !== "") {
                                Quickshell.execDetached(["bash", "-c", searchInput.text])
                                LauncherState.hide()
                            }
                        }
                        Keys.onEscapePressed: {
                            if (root._hiddenMenuOpen) root._closeHiddenMenu()
                            else LauncherState.hide()
                        }
                    }
                }
            }

            // ── App grid ─────────────────────────────────────────────────
            Item {
                width:  parent.width
                height: 348
                clip:   true

                // Background scroll + right-click (z:0, under icon delegates)
                MouseArea {
                    anchors.fill:    parent
                    z:               0
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y < 0) {
                            if (root.currentPage < root.totalPages - 1) root.currentPage++
                        } else {
                            if (root.currentPage > 0) root.currentPage--
                        }
                    }
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton)
                            root._openHiddenMenu()
                    }
                }

                Repeater {
                    id: appsRepeater
                    model: DesktopEntries.applications
                    onCountChanged: filterTimer.restart()

                    delegate: AppLauncherIcon {
                        appId:              modelData.id
                        appName:            modelData.name
                        appIcon:            modelData.icon
                        appData:            modelData
                        delegateIndex:      index
                        launcherItemsPerPage: root.itemsPerPage
                        launcherCurrentPage:  root.currentPage
                        launcherSelectedIdx:  root.selectedIndex
                        launcherIsGridView:   root.isGridView

                        // Write-back: icon sets selectedIndex on hover
                        onLauncherSelectedIdxChanged: {
                            if (root.selectedIndex !== launcherSelectedIdx)
                                root.selectedIndex = launcherSelectedIdx
                        }
                    }
                }
            }

            // ── Pagination dots ──────────────────────────────────────────
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                visible: root.totalPages > 1

                Repeater {
                    model: root.totalPages
                    Rectangle {
                        width:  8
                        height: 8
                        radius: 4
                        color:  index === root.currentPage ? PanelColors.launcher : PanelColors.border
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    root.currentPage = index
                        }
                    }
                }
            }
        }

        Keys.onEscapePressed: {
            if (root._hiddenMenuOpen) root._closeHiddenMenu()
            else LauncherState.hide()
        }
        focus: true
    }
}
