import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.desktop

// One desktop icon: labels, selection, double-click and drag handling.
Item {
    id: root

    property string fileName: ""
    property string filePath: ""
    property string fileURL: ""
    property bool fileIsDir: false
    property int iconIndex: 0
    property var container: null
    property int appearDelay: 0

    property bool isSelected: false
    property bool isDropTarget: false
    property color textColor: "white"

    signal openRequested()
    signal contextRequested(real x, real y)
    signal picked(bool ctrl, bool shift)
    signal dragStarted()
    signal dragMoved(real targetX, real targetY, real pointerX, real pointerY)
    signal dragFinished(real pointerX, real pointerY, bool ctrl)

    readonly property bool dragging: _dragging
    property bool _dragging: false

    // .desktop entry metadata
    readonly property bool isDesktopEntry: fileName.toLowerCase().endsWith(".desktop")
    property string entryName: DesktopIconCache.nameFor(root.filePath)
    property string entryIcon: DesktopIconCache.iconFor(root.filePath)
    property string resolvedIconKind: DesktopIconCache.kindFor(root.filePath)
    property string resolvedIconValue: DesktopIconCache.valueFor(root.filePath)
    readonly property string fileFlags: DesktopIconCache.flagsFor(root.filePath)
    readonly property var badges: {
        const result = [];
        if (fileFlags.includes("link"))
            result.push("link");
        if (fileFlags.includes("exec"))
            result.push("terminal");
        if (fileFlags.includes("readonly"))
            result.push("lock");
        return result;
    }
    readonly property string displayName: {
        if (!isDesktopEntry)
            return fileName;
        if (entryName !== "")
            return entryName;
        // Avoid flashing the raw "*.desktop" filename while the entry parses.
        return fileName.replace(/\.desktop$/i, "");
    }
    readonly property real scaleFactor: container ? container.zoomScale : 1
    readonly property bool showLabel: container ? container.cfg.showLabels : true

    readonly property string fileIconSource: {
        if (resolvedIconKind === "path" || resolvedIconKind === "filethumb")
            return resolvedIconValue === "" ? "" : "file://" + resolvedIconValue;
        if (resolvedIconKind === "name")
            return resolvedIconValue === "" ? "" : Quickshell.iconPath(resolvedIconValue, "text-x-generic");
        return "";
    }
    readonly property bool showFileIcon: !isDesktopEntry && resolvedIconKind !== "thumb" && fileIconSource !== ""

    readonly property string desktopIconSource: {
        if (!isDesktopEntry)
            return "";
        if (entryIcon === "")
            return Quickshell.iconPath("application-x-executable", "application-x-executable");
        if (entryIcon.startsWith("/"))
            return "file://" + entryIcon;
        return Quickshell.iconPath(entryIcon, "application-x-executable");
    }

    width: container.cellWidthValue
    height: container.cellHeightValue
    x: container.iconXFor(fileName, iconIndex)
    y: container.iconYFor(fileName, iconIndex)
    z: _dragging ? 100 : 1

    function parseDesktopEntry(content) {
        let name = "";
        let icon = "";
        let inEntry = false;
        for (const raw of String(content).split("\n")) {
            const line = raw.trim();
            if (line.startsWith("[") && line.endsWith("]")) {
                inEntry = line === "[Desktop Entry]";
                continue;
            }
            if (!inEntry)
                continue;
            if (name === "" && line.startsWith("Name="))
                name = line.substring(5);
            else if (icon === "" && line.startsWith("Icon="))
                icon = line.substring(5);
        }
        DesktopIconCache.store(root.filePath, { name: name, icon: icon });
    }

    Process {
        id: iconProcess
        command: [Directories.scriptPath + "/desktop-file-icon.sh", root.filePath]
        stdout: StdioCollector {
            onStreamFinished: root.applyFileIcon(text)
        }
    }

    function applyFileIcon(output) {
        const line = String(output).split("\n")[0];
        const parts = line.split("\t");
        const kind = line.trim() === "" ? "" : (parts[0] ?? "");
        const value = parts.length > 1 ? (parts[1] ?? "") : "";
        const flags = parts.length > 2 ? (parts[2] ?? "") : "";
        DesktopIconCache.store(root.filePath, {
            kind: kind,
            value: value,
            flags: flags,
            done: true
        });
    }

    opacity: 0
    scale: appearDelay > 0 ? 0.9 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: 130
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutBack
        }
    }

    Timer {
        id: appearTimer
        repeat: false
        onTriggered: {
            root.opacity = 1;
            root.scale = 1;
        }
    }

    function ensureIconMetadata() {
        if (fileIsDir || isDesktopEntry || filePath === "")
            return;
        if (DesktopIconCache.doneFor(filePath))
            return;
        iconProcess.running = true;
    }

    Component.onCompleted: {
        if (root.appearDelay > 0) {
            appearTimer.interval = root.appearDelay;
            appearTimer.start();
        } else {
            root.opacity = 1;
        }
        root.ensureIconMetadata();
    }

    onFilePathChanged: root.ensureIconMetadata()

    FileView {
        id: entryView
        path: root.isDesktopEntry ? root.filePath : ""
        watchChanges: true
        onLoaded: root.parseDesktopEntry(text())
        onFileChanged: root.parseDesktopEntry(text())
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Appearance.rounding.normal
        color: root.isDropTarget ? root.container.selectionFill(root.container.cfg.selectionOpacity + 0.2)
             : root.isSelected ? root.container.selectionFill(root.container.cfg.selectionOpacity)
             : mouseArea.containsMouse ? root.container.selectionFill(root.container.cfg.selectionOpacity * 0.45)
             : "transparent"
        border.width: root.isDropTarget ? 1 : 0
        border.color: root.container.selectionColorValue

        Behavior on color {
            ColorAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }
    }

    Item {
        id: iconBox
        width: Math.min(root.width - 14, 54 * root.scaleFactor)
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.showLabel ? 8 * root.scaleFactor : (root.height - height) / 2

        DirectoryIcon {
            anchors.fill: parent
            visible: !root.isDesktopEntry && !root.showFileIcon
            fileModelData: ({
                fileName: root.fileName,
                filePath: root.filePath,
                fileUrl: root.fileURL,
                fileIsDir: root.fileIsDir
            })
        }

        Image {
            anchors.fill: parent
            visible: root.isDesktopEntry || root.showFileIcon
            source: root.isDesktopEntry ? root.desktopIconSource : root.fileIconSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }

        Row {
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: 2
            }
            spacing: 2

            Repeater {
                model: root.badges

                delegate: Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    color: Qt.rgba(0, 0, 0, 0.65)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData
                        iconSize: 11
                        color: "white"
                    }
                }
            }
        }
    }

    Text {
        id: label
        anchors {
            top: iconBox.bottom
            topMargin: 4
            left: parent.left
            right: parent.right
            leftMargin: 6
            rightMargin: 6
        }
        visible: root.showLabel
        text: root.displayName
        color: root.textColor
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 2
        font.pixelSize: Math.max(9, Math.round(Appearance.font.pixelSize.smaller * root.scaleFactor))
        font.weight: Font.Medium
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.5)
        lineHeight: 0.95
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        property bool pressStarted: false
        property real downX: 0
        property real downY: 0

        onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            if (event.button === Qt.RightButton) {
                if (ctrl) {
                    root.picked(true, shift);
                    return;
                }
                const point = root.mapToItem(root.container, event.x, event.y);
                root.contextRequested(point.x, point.y);
                return;
            }
            root.picked(ctrl, shift);
            pressStarted = true;
            downX = event.x;
            downY = event.y;
        }

        onPositionChanged: event => {
            if (!pressStarted || !(event.buttons & Qt.LeftButton))
                return;
            const dx = event.x - downX;
            const dy = event.y - downY;
            if (!root._dragging && Math.sqrt(dx * dx + dy * dy) < 6)
                return;
            if (!root._dragging) {
                root._dragging = true;
                root.dragStarted();
            }
            const point = root.mapToItem(root.container, event.x, event.y);
            root.dragMoved(point.x - downX, point.y - downY, point.x, point.y);
        }

        onReleased: event => {
            if (!pressStarted)
                return;
            pressStarted = false;
            if (!root._dragging)
                return;
            const point = root.mapToItem(root.container, event.x, event.y);
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            root._dragging = false;
            root.dragFinished(point.x, point.y, ctrl);
        }

        onCanceled: {
            pressStarted = false;
            if (root._dragging) {
                root._dragging = false;
                root.dragFinished(-1, -1, false);
            }
        }

        onDoubleClicked: event => {
            if (event.button === Qt.LeftButton)
                root.openRequested();
        }
    }
}
