pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Own configuration file for the desktop add-on. Kept separate from the shell's
// config.json so installs survive illogical-impulse updates without patching it.
Singleton {
    id: root

    readonly property string filePath: `${Quickshell.env("HOME")}/.config/illogical-impulse/desktop-icons.json`
    property bool ready: false

    property alias enable: adapter.enable
    property alias showOnAllScreens: adapter.showOnAllScreens
    property alias showLabels: adapter.showLabels
    property alias persistPositions: adapter.persistPositions
    property alias autoArrange: adapter.autoArrange
    property alias snapToGrid: adapter.snapToGrid
    property alias gridMode: adapter.gridMode
    property alias cellWidth: adapter.cellWidth
    property alias cellHeight: adapter.cellHeight
    property alias margin: adapter.margin
    property alias selectionColor: adapter.selectionColor
    property alias selectionOpacity: adapter.selectionOpacity
    property alias textColor: adapter.textColor
    property alias bandColor: adapter.bandColor
    property alias bandOpacity: adapter.bandOpacity
    property alias language: adapter.language

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
            property bool enable: true
            property bool showOnAllScreens: false
            property bool showLabels: true
            property bool persistPositions: true
            property bool autoArrange: false
            property bool snapToGrid: false
            property string gridMode: "columns"
            property int cellWidth: 96
            property int cellHeight: 104
            property int margin: 24
            property string selectionColor: "#4A90D9"
            property real selectionOpacity: 0.35
            property string textColor: "#FFFFFF"
            property string bandColor: "#4A90D9"
            property real bandOpacity: 0.18
            property string language: "en"
        }
    }
}
