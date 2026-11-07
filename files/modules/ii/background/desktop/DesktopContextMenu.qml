import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Windows-like context menu for the desktop. Rendered inside the background
// surface (no extra layer-shell surface needed).
Item {
    id: root

    property var items: []
    property bool shown: false
    property real menuX: 0
    property real menuY: 0

    readonly property int itemHeight: 34
    readonly property int padding: 6
    readonly property int iconSlot: 18
    readonly property int iconSpacing: 10
    readonly property int rowMargins: 20
    readonly property int minWidth: 170
    readonly property int maxWidth: 480

    FontMetrics {
        id: labelMetrics
        font.pixelSize: Appearance.font.pixelSize.small
    }

    // Width follows the longest label (plus icon slot and row margins).
    readonly property real longestLabelWidth: {
        let longest = 0;
        for (const item of root.items) {
            if (!item || item.separator)
                continue;
            longest = Math.max(longest, labelMetrics.advanceWidth(item.label ?? ""));
        }
        return longest;
    }

    visible: shown
    z: 5000
    width: Math.min(root.maxWidth, Math.max(root.minWidth,
        root.longestLabelWidth + root.iconSlot + root.iconSpacing + root.rowMargins + root.padding * 2 + 4))
    height: column.implicitHeight + padding * 2
    x: Math.max(4, Math.min(menuX, parent ? parent.width - width - 4 : menuX))
    y: Math.max(4, Math.min(menuY, parent ? parent.height - height - 4 : menuY))

    function openAt(x, y, menuItems) {
        root.items = menuItems;
        root.menuX = x;
        root.menuY = y;
        root.shown = true;
    }

    function close() {
        root.shown = false;
    }

    StyledRectangularShadow {
        target: background
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Column {
        id: column
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 1

        Repeater {
            model: root.items
            delegate: Item {
                id: entry
                width: column.width
                height: modelData.separator ? 9 : root.itemHeight

                Rectangle {
                    visible: modelData.separator === true
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 8
                        rightMargin: 8
                    }
                    height: 1
                    color: Appearance.colors.colLayer0Border
                }

                Rectangle {
                    visible: modelData.separator !== true
                    anchors.fill: parent
                    radius: Appearance.rounding.verysmall
                    color: entryMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
                }

                Row {
                    visible: modelData.separator !== true
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 10

                    Image {
                        visible: (modelData.iconSource ?? "") !== ""
                        source: modelData.iconSource ?? ""
                        sourceSize.width: 18
                        sourceSize.height: 18
                        width: 18
                        height: 18
                        fillMode: Image.PreserveAspectFit
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MaterialSymbol {
                        visible: (modelData.iconSource ?? "") === ""
                        text: modelData.icon ?? ""
                        iconSize: 18
                        color: (modelData.enabled ?? true) ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer2
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: modelData.label ?? ""
                        color: (modelData.enabled ?? true) ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: entryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modelData.separator !== true && (modelData.enabled ?? true)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.close();
                        if (modelData.action)
                            modelData.action();
                    }
                }
            }
        }
    }
}
