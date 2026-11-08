import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

Item {
    id: root
    property var widgetData: ({})
    property var host: null

    ColumnLayout {
        visible: root.widgetData.style !== "analog"
        anchors.centerIn: parent
        spacing: 2

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(DesktopClock.now, "HH:mm")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: root.widgetData.style === "minimal" ? 44 : 46
            font.weight: Font.DemiBold
        }

        StyledText {
            visible: root.widgetData.style !== "minimal"
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(DesktopClock.now, "dddd, d MMMM")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    Canvas {
        id: analogCanvas
        visible: root.widgetData.style === "analog"
        width: Math.min(root.width, root.height) - 24
        height: width
        anchors.centerIn: parent

        Connections {
            target: DesktopClock
            function onNowChanged() {
                analogCanvas.requestPaint();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const size = Math.min(width, height);
            const cx = width / 2;
            const cy = height / 2;
            const radius = size / 2 - 6;
            const now = DesktopClock.now;

            ctx.beginPath();
            ctx.arc(cx, cy, radius, 0, Math.PI * 2);
            ctx.fillStyle = Qt.rgba(0.12, 0.12, 0.13, 0.9);
            ctx.fill();
            ctx.lineWidth = 2;
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25);
            ctx.stroke();

            for (let i = 0; i < 12; i++) {
                const angle = i / 12 * Math.PI * 2;
                const outer = radius - 4;
                const inner = radius - (i % 3 === 0 ? 16 : 10);
                ctx.beginPath();
                ctx.moveTo(cx + Math.sin(angle) * inner, cy - Math.cos(angle) * inner);
                ctx.lineTo(cx + Math.sin(angle) * outer, cy - Math.cos(angle) * outer);
                ctx.lineWidth = i % 3 === 0 ? 3 : 1.5;
                ctx.strokeStyle = Qt.rgba(1, 1, 1, i % 3 === 0 ? 0.8 : 0.4);
                ctx.stroke();
            }

            const hours = (now.getHours() % 12) + now.getMinutes() / 60;
            const minutes = now.getMinutes() + now.getSeconds() / 60;
            const seconds = now.getSeconds();

            const drawHand = (angle, length, lineWidth, color) => {
                ctx.beginPath();
                ctx.moveTo(cx, cy);
                ctx.lineTo(cx + Math.sin(angle) * length, cy - Math.cos(angle) * length);
                ctx.lineWidth = lineWidth;
                ctx.strokeStyle = color;
                ctx.lineCap = "round";
                ctx.stroke();
            };

            drawHand(hours / 12 * Math.PI * 2, radius * 0.5, 5, "white");
            drawHand(minutes / 60 * Math.PI * 2, radius * 0.72, 3, Qt.rgba(1, 1, 1, 0.85));
            drawHand(seconds / 60 * Math.PI * 2, radius * 0.82, 1.5, Appearance.colors.colPrimary);

            ctx.beginPath();
            ctx.arc(cx, cy, 4, 0, Math.PI * 2);
            ctx.fillStyle = Appearance.colors.colPrimary;
            ctx.fill();
        }
    }
}
