import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// Small confirmation dialog used before deleting files.
PanelWindow {
    id: root

    required property var desktop
    property string message: ""

    signal confirmed()
    signal dismissed()

    visible: true
    screen: desktop.screenRef ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:desktop-confirm"
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

    Rectangle {
        id: card
        x: (root.width - width) / 2 + root.dragOffsetX
        y: (root.height - height) / 2 + root.dragOffsetY
        width: Math.min(460, parent.width - 80)
        height: 170
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        focus: true

        Keys.onEscapePressed: root.dismissed()

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
                margins: 20
            }
            spacing: 14

            StyledText {
                Layout.fillWidth: true
                text: root.message
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.normal
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitWidth: 110
                    implicitHeight: 38
                    radius: Appearance.rounding.small
                    color: cancelMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

                    StyledText {
                        anchors.centerIn: parent
                        text: DesktopTranslation.tr("Cancel")
                        color: Appearance.colors.colOnLayer1
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissed()
                    }
                }

                Rectangle {
                    implicitWidth: 110
                    implicitHeight: 38
                    radius: Appearance.rounding.small
                    color: confirmMouse.containsMouse ? Appearance.colors.colErrorHover : Appearance.colors.colError

                    StyledText {
                        anchors.centerIn: parent
                        text: DesktopTranslation.tr("Delete")
                        color: Appearance.colors.colOnError
                    }

                    MouseArea {
                        id: confirmMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmed()
                    }
                }
            }
        }
    }
}
