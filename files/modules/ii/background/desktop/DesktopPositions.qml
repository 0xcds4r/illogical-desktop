pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Icon positions in the add-on's own state file, independent of the shell's
// states.json (which upstream may change).
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("HOME")}/.local/state/quickshell/user`
    readonly property string filePath: `${root.stateDir}/desktop-positions.json`
    property bool ready: false

    property alias iconPositions: adapter.iconPositions

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

    Timer {
        id: writeTimer
        interval: 80
        repeat: false
        onTriggered: view.writeAdapter()
    }

    Timer {
        id: reloadTimer
        interval: 80
        repeat: false
        onTriggered: view.reload()
    }

    FileView {
        id: view
        path: root.filePath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onAdapterUpdated: writeTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeTimer.restart();
        }

        adapter: JsonAdapter {
            id: adapter
            property list<string> iconPositions: []
        }
    }
}
