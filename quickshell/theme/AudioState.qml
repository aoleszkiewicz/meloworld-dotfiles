pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ── AudioState ────────────────────────────────────────────────────────────────
// Single source of truth for PulseAudio/PipeWire state.
// All mutations go through pactl; `pactl subscribe` keeps properties in sync.
Singleton {
    id: root

    // ── Public State ──────────────────────────────────────────────────────────
    property bool   popupVisible:  false
    property var    sinks:         []
    property var    sources:       []
    property string defaultSink:   ""
    property string defaultSource: ""
    property int    volume:        0
    property bool   muted:         false
    property int    micVolume:     0
    property bool   micMuted:      false

    // ── Popup Control ─────────────────────────────────────────────────────────
    function show() {
        SessionState.closeAllPopups()
        refreshAll()
        popupVisible = true
    }

    function hide() {
        popupVisible = false
    }

    // ── Refresh Helpers ───────────────────────────────────────────────────────
    // Each helper restarts the process regardless of whether it is already
    // running, so that callers always get a fresh read.

    function refreshSinks() {
        sinksProc.running = false
        sinksProc.running = true
    }

    function refreshSinkState() {
        defaultSinkProc.running = false
        defaultSinkProc.running = true
        volProc.running = false
        volProc.running = true
        muteProc.running = false
        muteProc.running = true
    }

    function refreshSources() {
        sourcesProc.running = false
        sourcesProc.running = true
    }

    function refreshSourceState() {
        defaultSourceProc.running = false
        defaultSourceProc.running = true
        micVolProc.running = false
        micVolProc.running = true
        micMuteProc.running = false
        micMuteProc.running = true
    }

    function refreshAll() {
        refreshSinks()
        refreshSinkState()
        refreshSources()
        refreshSourceState()
    }

    // ── Mutations ─────────────────────────────────────────────────────────────
    // NOTE: We do NOT optimistically update local state here.
    // `pactl subscribe` will fire and the debounce loop will re-query, keeping
    // a single authoritative source of truth and avoiding double-update races.

    function setDefaultSink(name) {
        Quickshell.execDetached(["pactl", "set-default-sink", name])
    }

    function setDefaultSource(name) {
        Quickshell.execDetached(["pactl", "set-default-source", name])
    }

    function setVolume(newVol) {
        Quickshell.execDetached(["pactl", "set-sink-volume", "@DEFAULT_SINK@", newVol + "%"])
    }

    function setMicVolume(newVol) {
        Quickshell.execDetached(["pactl", "set-source-volume", "@DEFAULT_SOURCE@", newVol + "%"])
    }

    function setMute(mute) {
        Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", mute ? "1" : "0"])
    }

    function setMicMute(mute) {
        Quickshell.execDetached(["pactl", "set-source-mute", "@DEFAULT_SOURCE@", mute ? "1" : "0"])
    }

    // ── Debounce state ────────────────────────────────────────────────────────
    // Kept at root scope for clarity; set by the subscribe parser.
    property bool _pendingSink:   false
    property bool _pendingSource: false

    Timer {
        id: debounceTimer
        interval: 80     // slightly longer window to coalesce rapid pactl events
        repeat:   false
        onTriggered: {
            if (root._pendingSink) {
                root.refreshSinks()
                root.refreshSinkState()
                root._pendingSink = false
            }
            if (root._pendingSource) {
                root.refreshSources()
                root.refreshSourceState()
                root._pendingSource = false
            }
        }
    }

    // ── pactl subscribe ───────────────────────────────────────────────────────
    Timer {
        id: subRestartTimer
        interval: 1500   // back-off before reconnecting after unexpected exit
        onTriggered: subscribeProc.running = true
    }

    Process {
        id: subscribeProc
        command: ["pactl", "subscribe"]
        running: true
        onRunningChanged: {
            if (!running) subRestartTimer.start()
        }
        stdout: SplitParser {
            // pactl subscribe emits lines like:
            //   Event 'change' on sink #0
            //   Event 'change' on source #1
            //   Event 'new' on sink-input #2
            // We key on the object type, not on substring presence, to avoid
            // false-positives (e.g. a source description that contains "sink").
            onRead: (line) => {
                const lower = line.toLowerCase()
                // Match "on sink" or "on sink-input" / "on sink-output"
                const hasSink   = / on sink/.test(lower)
                // Match "on source" but NOT "on source-output" hitting sink check
                const hasSource = / on source/.test(lower)

                if (hasSink)   { root._pendingSink   = true; debounceTimer.restart() }
                if (hasSource) { root._pendingSource = true; debounceTimer.restart() }
            }
        }
    }

    // ── Sink list ─────────────────────────────────────────────────────────────
    Process {
        id: sinksProc
        command: ["pactl", "list", "sinks"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines  = text.split("\n")
                const result = []
                let current  = {}
                for (const line of lines) {
                    const t = line.trim()
                    if (t.startsWith("Name:")) {
                        if (current.name) result.push(current)
                        current = { name: t.slice(5).trim() }
                    } else if (t.startsWith("Description:")) {
                        current.description = t.slice(12).trim()
                    }
                }
                if (current.name) result.push(current)
                root.sinks = result.filter(s => !s.name.includes(".monitor"))
            }
        }
    }

    // ── Source list ───────────────────────────────────────────────────────────
    Process {
        id: sourcesProc
        command: ["pactl", "list", "sources"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines  = text.split("\n")
                const result = []
                let current  = {}
                for (const line of lines) {
                    const t = line.trim()
                    if (t.startsWith("Name:")) {
                        if (current.name) result.push(current)
                        current = { name: t.slice(5).trim() }
                    } else if (t.startsWith("Description:")) {
                        current.description = t.slice(12).trim()
                    }
                }
                if (current.name) result.push(current)
                root.sources = result.filter(s => !s.name.includes(".monitor"))
            }
        }
    }

    // ── Default sink / source ─────────────────────────────────────────────────
    Process {
        id: defaultSinkProc
        command: ["pactl", "get-default-sink"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.defaultSink = text.trim()
        }
    }

    Process {
        id: defaultSourceProc
        command: ["pactl", "get-default-source"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.defaultSource = text.trim()
        }
    }

    // ── Volume ────────────────────────────────────────────────────────────────
    Process {
        id: volProc
        command: ["pactl", "get-sink-volume", "@DEFAULT_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)%/)
                if (m) root.volume = parseInt(m[1], 10)
            }
        }
    }

    // ── Mute ──────────────────────────────────────────────────────────────────
    Process {
        id: muteProc
        command: ["pactl", "get-sink-mute", "@DEFAULT_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.muted = text.includes("yes")
        }
    }

    // ── Mic volume ────────────────────────────────────────────────────────────
    Process {
        id: micVolProc
        command: ["pactl", "get-source-volume", "@DEFAULT_SOURCE@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/(\d+)%/)
                if (m) root.micVolume = parseInt(m[1], 10)
            }
        }
    }

    // ── Mic mute ──────────────────────────────────────────────────────────────
    Process {
        id: micMuteProc
        command: ["pactl", "get-source-mute", "@DEFAULT_SOURCE@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.micMuted = text.includes("yes")
        }
    }
}
