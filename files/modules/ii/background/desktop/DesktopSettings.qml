import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Modal desktop settings. Opened from the desktop context menu.
PanelWindow {
    id: root

    required property var desktop

    signal dismissed()

    visible: true
    screen: desktop.screenRef ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:desktop-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    readonly property var cfg: Config.options.background.desktopIcons
    readonly property int cardWidth: Math.min(1000, width - 80)
    readonly property int cardMaxHeight: height - 100


    component SectionLabel: StyledText {
        Layout.topMargin: 10
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: Appearance.colors.colPrimary
        opacity: 0.9
    }

    component ColorRow: RowLayout {
        id: colorRow
        property string label: ""
        property string value: "#FFFFFF"
        signal changed(string newValue)

        Layout.fillWidth: true
        spacing: 8

        StyledText {
            Layout.preferredWidth: 200
            text: colorRow.label
            color: Appearance.colors.colOnSecondaryContainer
        }

        Repeater {
            model: ["#4A90D9", "#4CAF50", "#FF9800", "#F44336", "#9C27B0", "#FFFFFF"]
            delegate: Rectangle {
                width: 20
                height: 20
                radius: 10
                color: modelData
                border.width: colorRow.value.toLowerCase() === modelData.toLowerCase() ? 2 : 1
                border.color: Appearance.colors.colOnLayer2

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: colorRow.changed(modelData)
                }
            }
        }

        TextInput {
            Layout.preferredWidth: 86
            text: colorRow.value
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            selectByMouse: true
            onEditingFinished: {
                if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(text))
                    colorRow.changed(text);
                else
                    text = colorRow.value;
            }
        }
    }

    component ActionButton: Rectangle {
        id: button
        property string label: ""
        property string icon: ""
        signal activated()

        implicitHeight: 38
        Layout.fillWidth: true
        radius: Appearance.rounding.small
        color: buttonMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
            }
            spacing: 10
            MaterialSymbol {
                text: button.icon
                iconSize: 18
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: button.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }

    // Swallow clicks outside the card: the modal closes only from its controls
    // (Done / close button / Escape), never by clicking the desktop.
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.cardWidth
        height: Math.min(root.cardMaxHeight, 150 + settingsColumn.implicitHeight)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        focus: true

        Keys.onEscapePressed: root.dismissed()

        // Swallow clicks so they do not reach the dim background.
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
                    text: "settings"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Desktop settings")
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
                contentHeight: settingsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: settingsColumn
                    width: parent.width
                    spacing: 6

                    SectionLabel { text: Translation.tr("General") }

                    ConfigSwitch {
                        buttonIcon: "desktop_windows"
                        text: Translation.tr("Show desktop icons")
                        checked: root.cfg.enable
                        onCheckedChanged: root.cfg.enable = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "branding_watermark"
                        text: Translation.tr("Show on all screens")
                        checked: root.cfg.showOnAllScreens
                        onCheckedChanged: root.cfg.showOnAllScreens = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "save"
                        text: Translation.tr("Remember positions")
                        checked: root.cfg.persistPositions
                        onCheckedChanged: root.cfg.persistPositions = checked
                    }

                    ConfigSwitch {
                        buttonIcon: "grid_on"
                        text: Translation.tr("Auto arrange")
                        checked: root.cfg.autoArrange
                        onCheckedChanged: {
                            root.cfg.autoArrange = checked;
                            if (checked)
                                root.desktop.resetPositions();
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "grid_4x4"
                        text: Translation.tr("Snap to grid")
                        checked: root.cfg.snapToGrid
                        onCheckedChanged: root.cfg.snapToGrid = checked
                    }

                    SectionLabel { text: Translation.tr("Grid") }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        StyledText {
                            Layout.preferredWidth: 120
                            text: Translation.tr("Direction")
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        ConfigSelectionArray {
                            Layout.fillWidth: true
                            currentValue: root.cfg.gridMode
                            options: [
                                { displayName: Translation.tr("Columns"), icon: "view_column", value: "columns" },
                                { displayName: Translation.tr("Rows"), icon: "view_stream", value: "rows" }
                            ]
                            onSelected: newValue => {
                                root.cfg.gridMode = newValue;
                                root.desktop.resetPositions();
                            }
                        }
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Cell width")
                        buttonIcon: "width"
                        usePercentTooltip: false
                        from: 64
                        to: 220
                        value: root.cfg.cellWidth
                        onValueChanged: root.cfg.cellWidth = Math.round(value)
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Cell height")
                        buttonIcon: "height"
                        usePercentTooltip: false
                        from: 64
                        to: 240
                        value: root.cfg.cellHeight
                        onValueChanged: root.cfg.cellHeight = Math.round(value)
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Margin")
                        buttonIcon: "border_outer"
                        usePercentTooltip: false
                        from: 8
                        to: 64
                        value: root.cfg.margin
                        onValueChanged: root.cfg.margin = Math.round(value)
                    }

                    SectionLabel { text: Translation.tr("Colors") }

                    ColorRow {
                        label: Translation.tr("Icon selection color")
                        value: root.cfg.selectionColor
                        onChanged: newValue => {
                            const previous = root.cfg.selectionColor;
                            root.cfg.selectionColor = newValue;
                            // Keep the rubber-band color in sync until it is customized.
                            if (root.cfg.bandColor.toLowerCase() === previous.toLowerCase())
                                root.cfg.bandColor = newValue;
                        }
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Icon selection opacity")
                        textWidth: 200
                        buttonIcon: "opacity"
                        usePercentTooltip: true
                        from: 0.05
                        to: 1
                        value: root.cfg.selectionOpacity
                        onValueChanged: root.cfg.selectionOpacity = value
                    }

                    ColorRow {
                        label: Translation.tr("Text color")
                        value: root.cfg.textColor
                        onChanged: newValue => root.cfg.textColor = newValue
                    }

                    ColorRow {
                        label: Translation.tr("Selection rectangle color")
                        value: root.cfg.bandColor
                        onChanged: newValue => root.cfg.bandColor = newValue
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Selection rectangle opacity")
                        textWidth: 200
                        buttonIcon: "opacity"
                        usePercentTooltip: true
                        from: 0.05
                        to: 0.6
                        value: root.cfg.bandOpacity
                        onValueChanged: root.cfg.bandOpacity = value
                    }

                    SectionLabel { text: Translation.tr("Arrange") }

                    ActionButton {
                        label: Translation.tr("Arrange by name")
                        icon: "sort_by_alpha"
                        onActivated: {
                            root.desktop.arrangeIcons("name");
                            root.dismissed();
                        }
                    }

                    ActionButton {
                        label: Translation.tr("Arrange by type")
                        icon: "category"
                        onActivated: {
                            root.desktop.arrangeIcons("type");
                            root.dismissed();
                        }
                    }

                    ActionButton {
                        label: Translation.tr("Arrange by size")
                        icon: "data_usage"
                        onActivated: {
                            root.desktop.arrangeIcons("size");
                            root.dismissed();
                        }
                    }

                    ActionButton {
                        label: Translation.tr("Arrange by date modified")
                        icon: "schedule"
                        onActivated: {
                            root.desktop.arrangeIcons("date");
                            root.dismissed();
                        }
                    }

                    ActionButton {
                        label: Translation.tr("Reset positions")
                        icon: "restart_alt"
                        onActivated: root.desktop.resetPositions()
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                    }
                }
            }

            ActionButton {
                label: Translation.tr("Done")
                icon: "check"
                onActivated: root.dismissed()
            }
        }
    }
}
