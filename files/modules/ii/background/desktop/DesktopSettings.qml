import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.desktop

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

    readonly property var cfg: DesktopConfig
    readonly property int cardWidth: Math.min(1000, width - 80)
    readonly property int cardMaxHeight: height - 100
    property int settingsTab: 0

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

    // Dim + swallow clicks outside the card.
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root.cardWidth
        height: Math.min(root.cardMaxHeight, 620)
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
                    text: "settings"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: DesktopTranslation.tr("Desktop settings")
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

            ConfigSelectionArray {
                Layout.fillWidth: true
                currentValue: root.settingsTab
                options: [
                    { displayName: DesktopTranslation.tr("General"), icon: "tune", value: 0 },
                    { displayName: DesktopTranslation.tr("Grid"), icon: "grid_view", value: 1 },
                    { displayName: DesktopTranslation.tr("Colors"), icon: "palette", value: 2 },
                    { displayName: DesktopTranslation.tr("Arrange"), icon: "sort", value: 3 },
                    { displayName: DesktopTranslation.tr("Language"), icon: "translate", value: 4 }
                ]
                onSelected: newValue => root.settingsTab = newValue
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

                    // ------------------------------------------------------- General
                    ColumnLayout {
                        visible: root.settingsTab === 0
                        Layout.fillWidth: true
                        spacing: 6

                        ConfigSwitch {
                            buttonIcon: "desktop_windows"
                            text: DesktopTranslation.tr("Show desktop icons")
                            checked: root.cfg.enable
                            onCheckedChanged: root.cfg.enable = checked
                        }

                        ConfigSwitch {
                            buttonIcon: "branding_watermark"
                            text: DesktopTranslation.tr("Show on all screens")
                            checked: root.cfg.showOnAllScreens
                            onCheckedChanged: root.cfg.showOnAllScreens = checked
                        }

                        ConfigSwitch {
                            buttonIcon: "label"
                            text: DesktopTranslation.tr("Show icon labels")
                            checked: root.cfg.showLabels
                            onCheckedChanged: root.cfg.showLabels = checked
                        }

                        ConfigSwitch {
                            buttonIcon: "save"
                            text: DesktopTranslation.tr("Remember positions")
                            checked: root.cfg.persistPositions
                            onCheckedChanged: root.cfg.persistPositions = checked
                        }

                        ConfigSwitch {
                            buttonIcon: "delete"
                            text: DesktopTranslation.tr("Show trash icon")
                            checked: root.cfg.showTrash
                            onCheckedChanged: root.cfg.showTrash = checked
                        }

                        ConfigSwitch {
                            buttonIcon: "delete"
                            text: DesktopTranslation.tr("Confirm before deleting")
                            checked: root.cfg.confirmDelete
                            onCheckedChanged: root.cfg.confirmDelete = checked
                        }

                        ConfigSwitch {
                            buttonIcon: "grid_on"
                            text: DesktopTranslation.tr("Auto arrange")
                            checked: root.cfg.autoArrange
                            onCheckedChanged: {
                                root.cfg.autoArrange = checked;
                                if (checked)
                                    root.desktop.resetPositions();
                            }
                        }

                        ConfigSwitch {
                            buttonIcon: "grid_4x4"
                            text: DesktopTranslation.tr("Snap to grid")
                            checked: root.cfg.snapToGrid
                            onCheckedChanged: root.cfg.snapToGrid = checked
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 10

                            StyledText {
                                Layout.preferredWidth: 200
                                text: DesktopTranslation.tr("Desktop folder")
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer1
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                Text {
                                    anchors {
                                        left: parent.left
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 8
                                    }
                                    visible: folderInput.text === ""
                                    text: "~/Desktop"
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                TextInput {
                                    id: folderInput
                                    anchors {
                                        fill: parent
                                        leftMargin: 8
                                        rightMargin: 8
                                    }
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: DesktopConfig.folder
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    selectByMouse: true
                                    clip: true
                                    onEditingFinished: DesktopConfig.folder = text.trim()
                                }
                            }
                        }
                    }

                    // ---------------------------------------------------------- Grid
                    ColumnLayout {
                        visible: root.settingsTab === 1
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            StyledText {
                                Layout.preferredWidth: 200
                                text: DesktopTranslation.tr("Direction")
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            ConfigSelectionArray {
                                Layout.fillWidth: true
                                currentValue: root.cfg.gridMode
                                options: [
                                    { displayName: DesktopTranslation.tr("Columns"), icon: "view_column", value: "columns" },
                                    { displayName: DesktopTranslation.tr("Rows"), icon: "view_stream", value: "rows" }
                                ]
                                onSelected: newValue => {
                                    root.cfg.gridMode = newValue;
                                    root.desktop.resetPositions();
                                }
                            }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            text: DesktopTranslation.tr("Cell width")
                            buttonIcon: "width"
                            usePercentTooltip: false
                            from: 64
                            to: 220
                            value: root.cfg.cellWidth
                            onValueChanged: {
                                root.cfg.cellWidth = Math.round(value);
                                root.desktop.resnapPositions();
                            }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            text: DesktopTranslation.tr("Cell height")
                            buttonIcon: "height"
                            usePercentTooltip: false
                            from: 64
                            to: 240
                            value: root.cfg.cellHeight
                            onValueChanged: {
                                root.cfg.cellHeight = Math.round(value);
                                root.desktop.resnapPositions();
                            }
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            text: DesktopTranslation.tr("Margin")
                            buttonIcon: "border_outer"
                            usePercentTooltip: false
                            from: 8
                            to: 64
                            value: root.cfg.margin
                            onValueChanged: {
                                root.cfg.margin = Math.round(value);
                                root.desktop.resnapPositions();
                            }
                        }
                    }

                    // -------------------------------------------------------- Colors
                    ColumnLayout {
                        visible: root.settingsTab === 2
                        Layout.fillWidth: true
                        spacing: 6

                        ColorRow {
                            label: DesktopTranslation.tr("Icon selection color")
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
                            text: DesktopTranslation.tr("Icon selection opacity")
                            textWidth: 200
                            buttonIcon: "opacity"
                            usePercentTooltip: true
                            from: 0.05
                            to: 1
                            value: root.cfg.selectionOpacity
                            onValueChanged: root.cfg.selectionOpacity = value
                        }

                        ColorRow {
                            label: DesktopTranslation.tr("Text color")
                            value: root.cfg.textColor
                            onChanged: newValue => root.cfg.textColor = newValue
                        }

                        ColorRow {
                            label: DesktopTranslation.tr("Selection rectangle color")
                            value: root.cfg.bandColor
                            onChanged: newValue => root.cfg.bandColor = newValue
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            text: DesktopTranslation.tr("Selection rectangle opacity")
                            textWidth: 200
                            buttonIcon: "opacity"
                            usePercentTooltip: true
                            from: 0.05
                            to: 0.6
                            value: root.cfg.bandOpacity
                            onValueChanged: root.cfg.bandOpacity = value
                        }
                    }

                    // ------------------------------------------------------- Arrange
                    ColumnLayout {
                        visible: root.settingsTab === 3
                        Layout.fillWidth: true
                        spacing: 6

                        ActionButton {
                            label: DesktopTranslation.tr("Arrange by name")
                            icon: "sort_by_alpha"
                            onActivated: {
                                root.desktop.arrangeIcons("name");
                                root.dismissed();
                            }
                        }

                        ActionButton {
                            label: DesktopTranslation.tr("Arrange by type")
                            icon: "category"
                            onActivated: {
                                root.desktop.arrangeIcons("type");
                                root.dismissed();
                            }
                        }

                        ActionButton {
                            label: DesktopTranslation.tr("Arrange by size")
                            icon: "data_usage"
                            onActivated: {
                                root.desktop.arrangeIcons("size");
                                root.dismissed();
                            }
                        }

                        ActionButton {
                            label: DesktopTranslation.tr("Arrange by date modified")
                            icon: "schedule"
                            onActivated: {
                                root.desktop.arrangeIcons("date");
                                root.dismissed();
                            }
                        }

                        ActionButton {
                            label: DesktopTranslation.tr("Reset positions")
                            icon: "restart_alt"
                            onActivated: root.desktop.resetPositions()
                        }
                    }

                    // ----------------------------------------------------- Language
                    ColumnLayout {
                        visible: root.settingsTab === 4
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: DesktopTranslation.tr("Language")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        ConfigSelectionArray {
                            Layout.fillWidth: true
                            currentValue: DesktopConfig.language
                            options: DesktopTranslation.languageOptions.map(option => ({
                                displayName: option.name,
                                icon: "translate",
                                value: option.code
                            }))
                            onSelected: newValue => DesktopConfig.language = newValue
                        }
                    }
                }
            }

            ActionButton {
                label: DesktopTranslation.tr("Done")
                icon: "check"
                onActivated: root.dismissed()
            }
        }
    }
}
