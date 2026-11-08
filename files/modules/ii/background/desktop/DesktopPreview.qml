import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// Quick look: preview the selected file with Space.
PanelWindow {
    id: root

    required property var desktop
    property string filePath: ""

    signal dismissed()

    visible: true
    screen: desktop.screenRef ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:desktop-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    mask: Region {
        item: card
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Draggable card: offsets are applied on top of the centered position.
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    function clampDragOffsets() {
        const limitX = Math.max(0, root.width - card.width) / 2;
        const limitY = Math.max(0, root.height - card.height) / 2;
        root.dragOffsetX = Math.max(-limitX, Math.min(limitX, root.dragOffsetX));
        root.dragOffsetY = Math.max(-limitY, Math.min(limitY, root.dragOffsetY));
    }

    readonly property string fileName: filePath.substring(filePath.lastIndexOf("/") + 1)
    readonly property string suffix: {
        const dot = fileName.lastIndexOf(".");
        return dot > 0 ? fileName.substring(dot + 1).toLowerCase() : "";
    }
    readonly property bool isImage: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif"].includes(suffix)
    readonly property bool isVideo: ["mp4", "webm", "mkv", "mov", "avi", "m4v"].includes(suffix)
    readonly property bool isPdf: suffix === "pdf"
    readonly property bool isText: ["txt", "md", "json", "js", "ts", "qml", "sh", "py", "c", "cpp",
        "h", "hpp", "css", "html", "xml", "yaml", "yml", "conf", "ini", "log", "desktop"].includes(suffix)

    property string textContent: ""
    property string thumbPath: ""

    Process {
        id: thumbProcess
        running: false
        command: [Directories.scriptPath + "/desktop-helper", "icon", root.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).split("\n")[0].split("\t");
                if (parts[0] === "filethumb" && parts.length > 1)
                    root.thumbPath = parts[1];
            }
        }
    }

    Process {
        id: textProcess
        running: false
        command: ["bash", "-c", 'head -c 200000 -- "$1"', "preview", root.filePath]
        stdout: StdioCollector {
            onStreamFinished: root.textContent = text
        }
    }

    Component.onCompleted: {
        if (root.isVideo || root.isPdf)
            thumbProcess.running = true;
        else if (root.isText)
            textProcess.running = true;
    }

    Rectangle {
        id: card
        x: (root.width - width) / 2 + root.dragOffsetX
        y: (root.height - height) / 2 + root.dragOffsetY
        width: Math.min(parent.width - 160, 1200)
        height: Math.min(parent.height - 140, 860)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        focus: true

        Keys.onEscapePressed: root.dismissed()
        Keys.onSpacePressed: root.dismissed()

        MouseArea {
            id: dragHandle
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor

            property point pressScene: Qt.point(0, 0)
            property real startOffsetX: 0
            property real startOffsetY: 0
            property bool moved: false

            onPressed: mouse => {
                const point = dragHandle.mapToItem(null, mouse.x, mouse.y);
                pressScene = point;
                startOffsetX = root.dragOffsetX;
                startOffsetY = root.dragOffsetY;
                moved = false;
            }

            onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton))
                    return;
                const point = dragHandle.mapToItem(null, mouse.x, mouse.y);
                const dx = point.x - pressScene.x;
                const dy = point.y - pressScene.y;
                if (!moved && Math.abs(dx) + Math.abs(dy) < 3)
                    return;
                moved = true;
                root.dragOffsetX = startOffsetX + dx;
                root.dragOffsetY = startOffsetY + dy;
                root.clampDragOffsets();
            }
        }

        ColumnLayout {
            anchors {
                fill: parent
                margins: 18
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "preview"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.fileName
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer1
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissed()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Image {
                    anchors.fill: parent
                    visible: root.isImage
                    source: root.isImage ? "file://" + root.filePath : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Image {
                    anchors.fill: parent
                    visible: (root.isVideo || root.isPdf) && root.thumbPath !== ""
                    source: root.thumbPath === "" ? "" : "file://" + root.thumbPath
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Flickable {
                    anchors.fill: parent
                    visible: root.isText
                    clip: true
                    contentWidth: width
                    contentHeight: previewText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    TextEdit {
                        id: previewText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        text: root.textContent
                        wrapMode: TextEdit.Wrap
                        color: Appearance.colors.colOnLayer1
                        selectionColor: Appearance.colors.colPrimary
                        selectedTextColor: Appearance.colors.colOnPrimary
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !root.isImage && !root.isText
                        && !((root.isVideo || root.isPdf) && root.thumbPath !== "")
                    text: DesktopTranslation.tr("No preview available")
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }
}
