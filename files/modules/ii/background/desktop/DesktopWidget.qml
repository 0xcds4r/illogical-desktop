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

    readonly property bool topStrip: info.type === "notes" || info.type === "paint" || info.type === "timer"

    Rectangle {
        visible: info.type !== "notes" && info.type !== "paint"
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
            default: return "";
            }
        }
        onLoaded: {
            if (item) {
                item.widgetData = root.info;
                item.host = root.host;
            }
        }
    }

    MouseArea {
        id: contextArea
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: event => {
            if (!root.host)
                return;
            const point = contextArea.mapToItem(root.host, event.x, event.y);
            root.host.showWidgetMenu(root.info, point.x, point.y);
        }
    }

    MouseArea {
        id: dragArea
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.topStrip ? 28 : parent.height
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.SizeAllCursor

        property real pressX: 0
        property real pressY: 0
        property real startX: 0
        property real startY: 0
        property bool moved: false

        onPressed: event => {
            if (event.button === Qt.RightButton) {
                if (root.host) {
                    const point = dragArea.mapToItem(root.host, event.x, event.y);
                    root.host.showWidgetMenu(root.info, point.x, point.y);
                }
                return;
            }
            pressX = event.x;
            pressY = event.y;
            startX = root.x;
            startY = root.y;
            moved = false;
        }

        onPositionChanged: event => {
            if (!(event.buttons & Qt.LeftButton))
                return;
            const dx = event.x - pressX;
            const dy = event.y - pressY;
            if (!moved && Math.abs(dx) + Math.abs(dy) < 4)
                return;
            moved = true;
            root.x = Math.max(0, startX + dx);
            root.y = Math.max(0, startY + dy);
        }

        onReleased: {
            if (moved)
                DesktopWidgets.update(root.info.id, { x: Math.round(root.x), y: Math.round(root.y) });
        }
    }
}
