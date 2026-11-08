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

    readonly property bool dark: widgetData.style === "board"
    readonly property color canvasColor: dark ? "#20252b" : "#f5f2ea"
    readonly property var palette: dark ? ["#ffffff", "#ff6b6b", "#ffd166", "#7bd389", "#6bb6ff"] : ["#222222", "#d64545", "#d9a400", "#3d8b40", "#2f6fd0"]

    property color brushColor: palette[0]
    property var strokes: []
    property bool baseLoaded: false
    property var currentStroke: null

    function saveCanvas() {
        if (root.widgetData.paintPath)
            canvas.save(root.widgetData.paintPath);
    }

    Image {
        id: baseImage
        visible: false
        source: root.widgetData.paintPath ? "file://" + root.widgetData.paintPath : ""
        onStatusChanged: {
            root.baseLoaded = status === Image.Ready;
            canvas.requestPaint();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.canvasColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)

        Canvas {
            id: canvas
            anchors {
                fill: parent
                topMargin: 40
                bottomMargin: 44
                leftMargin: 8
                rightMargin: 8
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                if (root.baseLoaded)
                    ctx.drawImage(baseImage.source, 0, 0, width, height);

                for (const stroke of root.strokes) {
                    if (stroke.points.length === 0)
                        continue;
                    ctx.beginPath();
                    ctx.strokeStyle = stroke.color;
                    ctx.lineWidth = stroke.width;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.moveTo(stroke.points[0].x, stroke.points[0].y);
                    for (let i = 1; i < stroke.points.length; i++)
                        ctx.lineTo(stroke.points[i].x, stroke.points[i].y);
                    ctx.stroke();
                }

                if (root.currentStroke) {
                    const stroke = root.currentStroke;
                    if (stroke.points.length > 0) {
                        ctx.beginPath();
                        ctx.strokeStyle = stroke.color;
                        ctx.lineWidth = stroke.width;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        ctx.moveTo(stroke.points[0].x, stroke.points[0].y);
                        for (let i = 1; i < stroke.points.length; i++)
                            ctx.lineTo(stroke.points[i].x, stroke.points[i].y);
                        ctx.stroke();
                    }
                }
            }
        }

        MouseArea {
            anchors {
                fill: canvas
            }
            cursorShape: Qt.CrossCursor
            onPressed: mouse => {
                root.currentStroke = { color: root.brushColor, width: 3, points: [{ x: mouse.x, y: mouse.y }] };
                canvas.requestPaint();
            }
            onPositionChanged: mouse => {
                if (!pressed || !root.currentStroke)
                    return;
                root.currentStroke.points.push({ x: mouse.x, y: mouse.y });
                canvas.requestPaint();
            }
            onReleased: {
                if (root.currentStroke) {
                    root.strokes = root.strokes.concat([root.currentStroke]);
                    root.currentStroke = null;
                    root.saveCanvas();
                }
            }
        }

        RowLayout {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 10
            }
            spacing: 6

            Repeater {
                model: root.palette
                delegate: Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: modelData
                    border.width: root.brushColor === modelData ? 2 : 1
                    border.color: root.dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.4)
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.brushColor = modelData
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 54
                implicitHeight: 26
                radius: 8
                color: clearMouse.containsMouse ? Qt.rgba(0, 0, 0, 0.12) : "transparent"
                border.width: 1
                border.color: root.dark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.2)

                StyledText {
                    anchors.centerIn: parent
                    text: DesktopTranslation.tr("Clear")
                    color: root.dark ? "#ffffff" : "#222222"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.strokes = [];
                        root.currentStroke = null;
                        root.baseLoaded = false;
                        if (root.widgetData.paintPath)
                            Quickshell.execDetached(["rm", "-f", root.widgetData.paintPath]);
                        canvas.requestPaint();
                    }
                }
            }
        }
    }
}
