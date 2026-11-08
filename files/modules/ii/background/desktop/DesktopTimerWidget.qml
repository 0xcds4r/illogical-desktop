import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

Item {
    id: root
    property var widgetData: ({})
    property var host: null

    property bool running: widgetData.timerRunning ?? false
    property real endTime: widgetData.timerEnd ?? 0
    property int duration: widgetData.timerDuration ?? 300000
    property int tick: 0
    property int remaining: {
        root.tick;
        return Math.max(0, running ? endTime - Date.now() : (root._pausedRemaining ?? duration));
    }

    property int _pausedRemaining: widgetData.timerDuration ?? 300000

    function formatTime(ms) {
        const total = Math.ceil(ms / 1000);
        const minutes = Math.floor(total / 60);
        const seconds = total % 60;
        return (minutes < 10 ? "0" : "") + minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function persist(patch) {
        DesktopWidgets.update(root.widgetData.id, patch);
    }

    function start() {
        let value = root.remaining;
        if (value <= 0)
            value = root.duration > 0 ? root.duration : 300000;
        root.endTime = Date.now() + value;
        root.running = true;
        persist({ timerRunning: true, timerEnd: root.endTime, timerDuration: value });
    }

    function pause() {
        root._pausedRemaining = root.remaining;
        root.running = false;
        persist({ timerRunning: false, timerEnd: 0, timerDuration: root._pausedRemaining });
    }

    function reset() {
        root.running = false;
        root._pausedRemaining = root.duration;
        persist({ timerRunning: false, timerEnd: 0, timerDuration: root.duration });
    }

    function openClocks() {
        Quickshell.execDetached(["gnome-clocks"]);
    }

    function addMinutes(minutes) {
        root.duration = Math.max(60000, root.duration + minutes * 60000);
        root._pausedRemaining = root.duration;
        if (root.running) {
            root.endTime += minutes * 60000;
            persist({ timerDuration: root.duration, timerEnd: root.endTime });
        } else {
            persist({ timerDuration: root.duration, timerRunning: false, timerEnd: 0 });
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.running
        onTriggered: {
            root.tick += 1;
            if (Date.now() >= root.endTime) {
                root.running = false;
                root._pausedRemaining = 0;
                persist({ timerRunning: false, timerEnd: 0 });
                Quickshell.execDetached(["notify-send", "Timer", "Time is up"]);
            }
        }
    }

    ColumnLayout {
        visible: root.widgetData.style !== "pill"
        anchors.centerIn: parent
        spacing: 8

        Canvas {
            id: ring
            Layout.preferredWidth: 180
            Layout.preferredHeight: 180
            Layout.alignment: Qt.AlignHCenter

            Connections {
                target: root
                function onTickChanged() {
                    ring.requestPaint();
                }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const size = Math.min(width, height);
                const cx = width / 2;
                const cy = height / 2;
                const radius = size / 2 - 8;
                const progress = root.duration > 0 ? Math.max(0, Math.min(1, root.remaining / root.duration)) : 0;

                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2);
                ctx.lineWidth = 8;
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12);
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress);
                ctx.lineWidth = 8;
                ctx.lineCap = "round";
                ctx.strokeStyle = Appearance.colors.colPrimary;
                ctx.stroke();
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.formatTime(root.remaining)
            color: Appearance.colors.colOnLayer1
            font.pixelSize: 30
            font.weight: Font.DemiBold
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            TimerButton { label: "+1"; onClicked: root.addMinutes(1) }
            TimerButton { label: DesktopTranslation.tr("Start"); onClicked: root.start() }
            TimerButton { label: DesktopTranslation.tr("Pause"); onClicked: root.pause() }
            TimerButton { label: DesktopTranslation.tr("Reset"); onClicked: root.reset() }
            TimerIconButton { icon: "alarm"; onClicked: root.openClocks() }
        }
    }

    RowLayout {
        visible: root.widgetData.style === "pill"
        anchors.centerIn: parent
        spacing: 12

        StyledText {
            text: root.formatTime(root.remaining)
            color: Appearance.colors.colOnLayer1
            font.pixelSize: 30
            font.weight: Font.DemiBold
        }

        TimerButton { label: "+5"; onClicked: root.addMinutes(5) }
        TimerButton { label: DesktopTranslation.tr("Start"); onClicked: root.start() }
        TimerButton { label: DesktopTranslation.tr("Pause"); onClicked: root.pause() }
        TimerButton { label: DesktopTranslation.tr("Reset"); onClicked: root.reset() }
        TimerIconButton { icon: "alarm"; onClicked: root.openClocks() }
    }

    component TimerButton: Rectangle {
        property string label: ""
        signal clicked()
        implicitWidth: Math.max(34, buttonLabel.implicitWidth + 16)
        implicitHeight: 28
        radius: 8
        color: buttonMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

        StyledText {
            id: buttonLabel
            anchors.centerIn: parent
            text: parent.label
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component TimerIconButton: Rectangle {
        property string icon: "alarm"
        signal clicked()
        implicitWidth: 28
        implicitHeight: 28
        radius: 8
        color: iconMouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

        MaterialSymbol {
            anchors.centerIn: parent
            text: parent.icon
            iconSize: 18
            color: Appearance.colors.colOnLayer1
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

}
