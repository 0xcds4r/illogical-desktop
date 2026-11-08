import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// File/folder properties dialog, opened from the icon context menu.
PanelWindow {
    id: root

    required property var desktop
    property string filePath: ""

    signal dismissed()

    visible: true
    screen: desktop.screenRef ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:desktop-properties"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property var infoRows: []

    readonly property int cardWidth: Math.min(640, width - 80)
    readonly property int cardMaxHeight: height - 120

    Process {
        id: propsProcess
        running: false
        command: [Directories.scriptPath + "/desktop-helper", "props", root.filePath]
        stdout: StdioCollector {
            onStreamFinished: root.applyProps(text)
        }
    }

    function applyProps(output) {
        const rows = [];
        for (const line of String(output).split("\n")) {
            if (line.trim() === "")
                continue;
            const parts = line.split("\t");
            if (parts.length < 2)
                continue;
            const label = parts[0];
            const value = parts.slice(1).join("\t");
            rows.push({
                label: DesktopTranslation.tr(label),
                value: label === "Type" ? DesktopTranslation.tr(value) : value
            });
        }
        root.infoRows = rows;
    }

    Component.onCompleted: propsProcess.running = true

    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.cardWidth
        height: Math.min(root.cardMaxHeight, 160 + rowsColumn.implicitHeight)
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
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "info"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: DesktopTranslation.tr("Properties")
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

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: rowsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rowsColumn
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.infoRows

                        delegate: RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            StyledText {
                                Layout.preferredWidth: 110
                                Layout.alignment: Qt.AlignTop
                                text: modelData.label
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.value
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: doneMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

                StyledText {
                    anchors.centerIn: parent
                    text: DesktopTranslation.tr("Done")
                    color: Appearance.colors.colOnLayer1
                }

                MouseArea {
                    id: doneMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissed()
                }
            }
        }
    }
}
