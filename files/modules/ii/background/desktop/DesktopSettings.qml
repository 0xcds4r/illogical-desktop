import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
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

    readonly property var cfg: DesktopConfig
    readonly property string helperPath: Directories.scriptPath + "/desktop-helper"
    property var appList: []
    property var selectedApps: ({})
    property string appSearch: ""
    property string shortcutStatus: ""
    readonly property int selectedAppCount: Object.keys(selectedApps).length
    readonly property var filteredApps: {
        const query = root.appSearch.toLowerCase().trim();
        if (query === "")
            return root.appList;
        return root.appList.filter(app =>
            app.name.toLowerCase().includes(query) || app.id.toLowerCase().includes(query));
    }

    Process {
        id: appsProcess
        running: false
        command: [root.helperPath, "apps"]
        stdout: StdioCollector {
            onStreamFinished: root.applyApps(text)
        }
    }

    function loadApps() {
        if (root.appList.length === 0 && !appsProcess.running)
            appsProcess.running = true;
    }

    function applyApps(output) {
        const apps = [];
        for (const line of String(output).split("\n")) {
            if (line.trim() === "")
                continue;
            const parts = line.split("\t");
            if (parts.length < 4)
                continue;
            apps.push({ id: parts[0], name: parts[1], icon: parts[2], path: parts[3] });
        }
        root.appList = apps;
    }

    function toggleApp(path) {
        const map = Object.assign({}, root.selectedApps);
        if (map[path])
            delete map[path];
        else
            map[path] = true;
        root.selectedApps = map;
    }

    function selectAllApps() {
        const map = Object.assign({}, root.selectedApps);
        for (const app of root.filteredApps)
            map[app.path] = true;
        root.selectedApps = map;
    }

    function clearApps() {
        root.selectedApps = ({});
    }

    function createShortcuts() {
        let count = 0;
        for (const path of Object.keys(root.selectedApps)) {
            Quickshell.execDetached([root.helperPath, "shortcut", path, root.desktop.desktopFolderPath]);
            count++;
        }
        root.selectedApps = ({});
        root.shortcutStatus = DesktopTranslation.tr("Created shortcuts") + ": " + count;
        root.desktop.scheduleRefresh();
    }

    onSettingsTabChanged: {
        if (root.settingsTab === 5)
            root.loadApps();
    }
    readonly property int cardWidth: Math.min(1000, width - 80)
    readonly property int cardMaxHeight: height - 100
    property int settingsTab: 0

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

    Rectangle {
        id: card
        x: (root.width - width) / 2 + root.dragOffsetX
        y: (root.height - height) / 2 + root.dragOffsetY
        width: root.cardWidth
        height: Math.min(root.cardMaxHeight, 620)
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
                    { displayName: DesktopTranslation.tr("Language"), icon: "translate", value: 4 },
                    { displayName: DesktopTranslation.tr("Applications"), icon: "apps", value: 5 },
                    { displayName: DesktopTranslation.tr("Widgets"), icon: "widgets", value: 6 }
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

                        DesktopColorRow {
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
                            textWidth: 290
                            buttonIcon: "opacity"
                            usePercentTooltip: true
                            from: 0.05
                            to: 1
                            value: root.cfg.selectionOpacity
                            onValueChanged: root.cfg.selectionOpacity = value
                        }

                        DesktopColorRow {
                            label: DesktopTranslation.tr("Text color")
                            value: root.cfg.textColor
                            onChanged: newValue => root.cfg.textColor = newValue
                        }

                        DesktopColorRow {
                            label: DesktopTranslation.tr("Selection rectangle color")
                            value: root.cfg.bandColor
                            onChanged: newValue => root.cfg.bandColor = newValue
                        }

                        ConfigSlider {
                            Layout.fillWidth: true
                            text: DesktopTranslation.tr("Selection rectangle opacity")
                            textWidth: 290
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

                    // -------------------------------------------------- Applications
                    ColumnLayout {
                        visible: root.settingsTab === 5
                        Layout.fillWidth: true
                        spacing: 8

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
                                    leftMargin: 10
                                }
                                visible: appSearchInput.text === ""
                                text: DesktopTranslation.tr("Search applications")
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            TextInput {
                                id: appSearchInput
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 10
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                text: root.appSearch
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                selectByMouse: true
                                onTextChanged: root.appSearch = text
                            }
                        }

                        ListView {
                            id: appsView
                            Layout.fillWidth: true
                            Layout.preferredHeight: 260
                            clip: true
                            spacing: 2
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.filteredApps

                            delegate: Rectangle {
                                id: appRow
                                width: ListView.view.width
                                height: 46
                                radius: Appearance.rounding.verysmall
                                color: root.selectedApps[modelData.path] ? Appearance.colors.colPrimaryContainer
                                     : rowMouse.containsMouse ? Appearance.colors.colLayer1Hover
                                     : "transparent"

                                RowLayout {
                                    anchors {
                                        fill: parent
                                        leftMargin: 8
                                        rightMargin: 10
                                    }
                                    spacing: 10

                                    Image {
                                        Layout.preferredWidth: 26
                                        Layout.preferredHeight: 26
                                        sourceSize.width: 26
                                        sourceSize.height: 26
                                        fillMode: Image.PreserveAspectFit
                                        source: modelData.icon === ""
                                            ? Quickshell.iconPath("application-x-executable", "application-x-executable")
                                            : modelData.icon.startsWith("/")
                                                ? "file://" + modelData.icon
                                                : Quickshell.iconPath(modelData.icon, "application-x-executable")
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.small
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.id
                                            elide: Text.ElideRight
                                            color: Appearance.colors.colOnLayer2
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                        }
                                    }

                                    MaterialSymbol {
                                        text: root.selectedApps[modelData.path] ? "check_box" : "check_box_outline_blank"
                                        iconSize: 20
                                        color: root.selectedApps[modelData.path] ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleApp(modelData.path)
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ActionButton {
                                label: DesktopTranslation.tr("Select all")
                                icon: "done_all"
                                onActivated: root.selectAllApps()
                            }

                            ActionButton {
                                label: DesktopTranslation.tr("Clear selection")
                                icon: "close"
                                onActivated: root.clearApps()
                            }
                        }

                        ActionButton {
                            label: DesktopTranslation.tr("Create shortcuts")
                                + (root.selectedAppCount > 0 ? " (" + root.selectedAppCount + ")" : "")
                            icon: "add"
                            onActivated: root.createShortcuts()
                        }

                        StyledText {
                            visible: root.shortcutStatus !== ""
                            text: root.shortcutStatus
                            color: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    // -------------------------------------------------------- Widgets
                    ColumnLayout {
                        visible: root.settingsTab === 6
                        Layout.fillWidth: true
                        spacing: 5

                        StyledText {
                            Layout.topMargin: 2
                            text: DesktopTranslation.tr("Custom widgets (Lua)")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: DesktopTranslation.tr("Create example"); icon: "description"; onActivated: DesktopWidgets.createExample() }
                            ActionButton { label: DesktopTranslation.tr("Open folder"); icon: "folder_open"; onActivated: DesktopWidgets.openCustomFolder() }
                        }

                        Repeater {
                            model: customModel

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                MaterialSymbol {
                                    text: "code"
                                    iconSize: 16
                                    color: Appearance.colors.colOnLayer2
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: model.fileName
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                ActionButton {
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: 120
                                    label: DesktopTranslation.tr("Add")
                                    icon: "add"
                                    onActivated: DesktopWidgets.addCustom(model.filePath)
                                }
                            }
                        }

                        StyledText {
                            visible: customModel.count === 0
                            text: DesktopTranslation.tr("No custom widgets found")
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        StyledText {
                            text: DesktopTranslation.tr("Clock")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: "Digital"; icon: "schedule"; onActivated: DesktopWidgets.add("clock", "digital") }
                            ActionButton { label: "Analog"; icon: "watch"; onActivated: DesktopWidgets.add("clock", "analog") }
                            ActionButton { label: "Minimal"; icon: "more_horiz"; onActivated: DesktopWidgets.add("clock", "minimal") }
                        }

                        StyledText {
                            Layout.topMargin: 2
                            text: DesktopTranslation.tr("Calendar")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: "Month"; icon: "calendar_month"; onActivated: DesktopWidgets.add("calendar", "month") }
                            ActionButton { label: "Compact"; icon: "today"; onActivated: DesktopWidgets.add("calendar", "compact") }
                        }

                        StyledText {
                            Layout.topMargin: 2
                            text: DesktopTranslation.tr("Date & time")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: "Stacked"; icon: "view_agenda"; onActivated: DesktopWidgets.add("datetime", "stacked") }
                            ActionButton { label: "Inline"; icon: "view_stream"; onActivated: DesktopWidgets.add("datetime", "inline") }
                        }

                        StyledText {
                            Layout.topMargin: 2
                            text: DesktopTranslation.tr("Notes")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: "Yellow"; icon: "sticky_note_2"; onActivated: DesktopWidgets.add("notes", "yellow") }
                            ActionButton { label: "Pink"; icon: "sticky_note_2"; onActivated: DesktopWidgets.add("notes", "pink") }
                            ActionButton { label: "Blue"; icon: "sticky_note_2"; onActivated: DesktopWidgets.add("notes", "blue") }
                            ActionButton { label: "Green"; icon: "sticky_note_2"; onActivated: DesktopWidgets.add("notes", "green") }
                        }

                        StyledText {
                            Layout.topMargin: 2
                            text: DesktopTranslation.tr("Timer / Alarm")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: "Ring"; icon: "timer"; onActivated: DesktopWidgets.add("timer", "ring") }
                            ActionButton { label: "Pill"; icon: "hourglass_empty"; onActivated: DesktopWidgets.add("timer", "pill") }
                        }

                        StyledText {
                            Layout.topMargin: 2
                            text: DesktopTranslation.tr("Mini paint")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colPrimary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ActionButton { label: "Paper"; icon: "palette"; onActivated: DesktopWidgets.add("paint", "paper") }
                            ActionButton { label: "Board"; icon: "draw"; onActivated: DesktopWidgets.add("paint", "board") }
                        }

                        ActionButton {
                            Layout.topMargin: 4
                            label: DesktopTranslation.tr("Remove all widgets")
                            icon: "delete_sweep"
                            onActivated: DesktopWidgets.removeAll()
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

    FolderListModel {
        id: customModel
        folder: DesktopWidgets.customDirUrl
        nameFilters: ["*.lua"]
        showDirs: false
        showHidden: false
    }
}
