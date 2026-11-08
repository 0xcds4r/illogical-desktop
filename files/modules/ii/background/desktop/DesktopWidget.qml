import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// One desktop widget instance: glass card, drag to move, right-click menu.
Item {
    id: root

    property var widgetData: ({})
    property var host: null

    readonly property var info: widgetData ?? ({})

    x: info.x ?? 0
    y: info.y ?? 0
    width: info.width ?? 0
    height: info.height ?? 0
    z: 10

    property string menuButton: info.menuButton ?? "right"

    readonly property bool menuOnRight: root.menuButton === "right"
    readonly property bool menuOnMiddle: root.menuButton === "middle"
    readonly property bool menuDisabled: root.menuButton === "none"
    readonly property string keyboardMenu: (!root.menuOnRight && !root.menuOnMiddle
        && !root.menuDisabled) ? root.menuButton : ""

    readonly property bool topStrip: info.drag !== "all" && (info.type === "notes"
        || info.type === "paint" || info.type === "timer" || info.type === "custom")
    readonly property int grabHeight: root.topStrip ? 34 : root.height

    // Drag in scene coordinates: the item moves under the cursor, so local
    // deltas would feed back into each other and make the widget jitter.
    property real pressSceneX: 0
    property real pressSceneY: 0
    property real startX: 0
    property real startY: 0
    property bool dragging: false

    function openKeyboardMenu() {
        if (!root.host)
            return;
        const point = root.mapToItem(root.host, root.width / 2, Math.min(48, root.height / 2));
        root.host.showWidgetMenu(root.info, point.x, point.y);
    }

    function beginDrag(area, event) {
        const point = area.mapToItem(null, event.x, event.y);
        root.pressSceneX = point.x;
        root.pressSceneY = point.y;
        root.startX = root.x;
        root.startY = root.y;
        root.dragging = false;
    }

    function moveDrag(area, event) {
        const point = area.mapToItem(null, event.x, event.y);
        const dx = point.x - root.pressSceneX;
        const dy = point.y - root.pressSceneY;
        if (!root.dragging && Math.abs(dx) + Math.abs(dy) < 4)
            return;
        root.dragging = true;
        const maxX = root.parent ? Math.max(0, root.parent.width - root.width) : 1e9;
        const maxY = root.parent ? Math.max(0, root.parent.height - root.height) : 1e9;
        root.x = Math.max(0, Math.min(maxX, root.startX + dx));
        root.y = Math.max(0, Math.min(maxY, root.startY + dy));
        root.z = 1000;
    }

    function endDrag(area, event, button) {
        if (root.dragging) {
            root.dragging = false;
            DesktopWidgets.update(root.info.id, { x: Math.round(root.x), y: Math.round(root.y) });
            return;
        }
        if (((button === Qt.RightButton && root.menuOnRight)
                || (button === Qt.MiddleButton && root.menuOnMiddle)) && root.host) {
            const point = area.mapToItem(root.host, event.x, event.y);
            root.host.showWidgetMenu(root.info, point.x, point.y);
        }
    }

    Rectangle {
        visible: info.type !== "notes" && info.type !== "paint" && info.type !== "custom"
        anchors.fill: parent
        radius: 18
        color: Qt.rgba(0.07, 0.07, 0.08, 0.72)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
    }

    Loader {
        id: content
        anchors.fill: parent
        source: {
            switch (root.info.type) {
            case "clock": return "DesktopClockWidget.qml";
            case "calendar": return "DesktopCalendarWidget.qml";
            case "datetime": return "DesktopDateTimeWidget.qml";
            case "notes": return "DesktopNotesWidget.qml";
            case "timer": return "DesktopTimerWidget.qml";
            case "paint": return "DesktopPaintWidget.qml";
            case "custom": return "DesktopLuaWidget.qml";
            default: return "";
            }
        }
        onLoaded: {
            if (item) {
                item.widgetData = root.info;
                item.host = root.host;
                if (item.menuButton !== undefined)
                    item.menuButton = root.menuButton;
                if (item.menuButtonRequested !== undefined)
                    item.menuButtonRequested.connect(button => root.menuButton = button);
                if (item.contextMenuRequested !== undefined)
                    item.contextMenuRequested.connect(() => root.openKeyboardMenu());
            }
        }
    }

    // Right button works anywhere on the widget: drag to move, release without
    // moving opens the menu.
    onMenuButtonChanged: {
        if (content.item && content.item.menuButton !== undefined)
            content.item.menuButton = root.menuButton;
    }

    MouseArea {
        id: contextArea
        anchors.fill: parent
        acceptedButtons: root.menuOnMiddle ? Qt.MiddleButton
            : (root.menuOnRight ? Qt.RightButton : Qt.NoButton)
        onPressed: event => root.beginDrag(contextArea, event)
        onPositionChanged: event => {
            if (event.buttons & Qt.RightButton)
                root.moveDrag(contextArea, event);
        }
        onReleased: event => root.endDrag(contextArea, event, event.button)
    }

    MouseArea {
        id: dragArea
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.grabHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.SizeAllCursor
        onPressed: event => root.beginDrag(dragArea, event)
        onPositionChanged: event => {
            if (event.buttons & (Qt.LeftButton | Qt.RightButton | Qt.MiddleButton))
                root.moveDrag(dragArea, event);
        }
        onReleased: event => root.endDrag(dragArea, event, event.button)
    }
}
