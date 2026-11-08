pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Shared one-second clock tick for desktop widgets.
Singleton {
    id: root

    property date now: new Date()

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
}
