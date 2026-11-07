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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, parent.width - 80)
        height: 170
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        focus: true

        Keys.onEscapePressed: root.dismissed()

        MouseArea {
            anchors.fill: parent
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
