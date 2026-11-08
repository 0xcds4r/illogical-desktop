import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// A desktop widget driven by a user-written Lua script.
Item {
    id: root

    property var widgetData: ({})
    property var host: null

    readonly property string scriptPath: widgetData.script ?? ""
    readonly property string statePath: DesktopWidgets.paintDir + "/lua-state-" + (widgetData.id ?? "widget") + ".lua"
    readonly property string runtime: DesktopWidgets.luaRuntime

    property var ops: []
    property var imageCache: ({})
    property int tickInterval: 0
    property string errorText: ""
    property bool started: false

    function send(line) {
        if (proc.running)
            proc.write(line + "\n");
    }

    function repaint() {
        canvas.requestPaint();
    }

    function handleLine(line) {
        if (!line || line.trim() === "")
            return;
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            console.log("lua widget:", line);
            return;
        }
        const meta = message.meta;
        if (meta) {
            const width = Math.round(meta.width ?? 0);
            const height = Math.round(meta.height ?? 0);
            root.tickInterval = Math.max(0, Math.round(meta.tick ?? 0));
            if (width > 0 && height > 0
                    && (Math.abs(width - (root.widgetData.width ?? 0)) > 1
                        || Math.abs(height - (root.widgetData.height ?? 0)) > 1)) {
                DesktopWidgets.update(root.widgetData.id, { width: width, height: height });
            }
        }
        root.errorText = message.error ? String(message.error) : "";
        root.ops = message.ops ?? [];
        root.repaint();
    }

    function buttonName(button) {
        if (button === Qt.RightButton)
            return "right";
        if (button === Qt.MiddleButton)
            return "middle";
        return "left";
    }

    function startHost() {
        const data = root.widgetData ?? ({});
        const script = data.script ?? "";
        if (script === "")
            return;
        const state = DesktopWidgets.paintDir + "/lua-state-" + (data.id ?? "widget") + ".lua";
        proc.command = [root.runtime, DesktopWidgets.luaHostPath, script, state];
        proc.running = true;
    }

    function restartHost() {
        root.started = false;
        proc.running = false;
        restartTimer.restart();
    }

    onScriptPathChanged: root.startHost()
    Component.onCompleted: root.startHost()

    Connections {
        target: DesktopWidgets
        function onReloadCounterChanged() {
            if (DesktopWidgets.reloadId === root.widgetData.id)
                root.restartHost();
        }
    }

    Timer {
        id: restartTimer
        interval: 150
        repeat: false
        onTriggered: proc.running = true
    }

    Process {
        id: proc
        running: false
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }

        stderr: SplitParser {
            onRead: data => {
                root.errorText = data;
                root.repaint();
            }
        }

        onRunningChanged: {
            if (!proc.running)
                return;
            root.started = true;
            root.send("i\t" + root.width + "\t" + root.height + "\t" + (root.widgetData.style ?? ""));
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.errorText === "")
                root.errorText = DesktopTranslation.tr("Lua exited with code") + " " + exitCode;
            root.repaint();
        }
    }

    Timer {
        interval: root.tickInterval
        repeat: true
        running: root.tickInterval > 0
        onTriggered: root.send("t\t" + Date.now())
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const list = root.ops ?? [];
            for (let i = 0; i < list.length; i++)
                root.paintOp(ctx, list[i] ?? ({}));
        }
    }

    MouseArea {
        id: input
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => root.send("p\t" + Math.round(mouse.x) + "\t" + Math.round(mouse.y)
            + "\t" + root.buttonName(mouse.button))
        onPositionChanged: mouse => {
            if (pressed)
                root.send("m\t" + Math.round(mouse.x) + "\t" + Math.round(mouse.y)
                    + "\t" + (mouse.buttons & Qt.LeftButton ? "left" : "other"));
        }
        onReleased: mouse => root.send("r\t" + Math.round(mouse.x) + "\t" + Math.round(mouse.y)
            + "\t" + root.buttonName(mouse.button))
        onDoubleClicked: mouse => root.send("d\t" + Math.round(mouse.x) + "\t" + Math.round(mouse.y))
        onWheel: wheel => root.send("w\t" + Math.round(wheel.angleDelta.y))
    }

    function number(value, fallback) {
        return (typeof value === "number" && isFinite(value)) ? value : fallback;
    }

    function roundedPath(ctx, x, y, w, h, radius) {
        const r = Math.max(0, Math.min(number(radius, 0), Math.min(w, h) / 2));
        ctx.beginPath();
        if (r <= 0) {
            ctx.rect(x, y, w, h);
            return;
        }
        ctx.moveTo(x + r, y);
        ctx.lineTo(x + w - r, y);
        ctx.arcTo(x + w, y, x + w, y + r, r);
        ctx.lineTo(x + w, y + h - r);
        ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
        ctx.lineTo(x + r, y + h);
        ctx.arcTo(x, y + h, x, y + h - r, r);
        ctx.lineTo(x, y + r);
        ctx.arcTo(x, y, x + r, y, r);
        ctx.closePath();
    }

    function paintText(ctx, op) {
        ctx.fillStyle = String(op.color ?? "#ffffff");
        ctx.font = number(op.size, 14) + "px " + String(op.font ?? "sans-serif");
        ctx.textAlign = String(op.align ?? "left");
        ctx.textBaseline = op.valign === "middle" ? "middle" : "alphabetic";
        const x = number(op.x, 0);
        const y = number(op.y, 0);
        for (const line of String(op.text ?? "").split("\n"))
            ctx.fillText(line, x, y);
    }

    function paintImage(ctx, op) {
        const src = String(op.src ?? "");
        if (src === "")
            return;
        let image = root.imageCache[src];
        if (!image) {
            image = Qt.createQmlObject("import QtQuick; Image { visible: false; asynchronous: true; smooth: true }",
                root, "luaWidgetImage");
            image.source = src;
            image.statusChanged.connect(() => canvas.requestPaint());
            const cache = Object.assign({}, root.imageCache);
            cache[src] = image;
            root.imageCache = cache;
        }
        if (image.status !== Image.Ready)
            return;
        ctx.drawImage(image, number(op.x, 0), number(op.y, 0),
            number(op.w, image.width), number(op.h, image.height));
    }

    function paintOp(ctx, op) {
        const type = String(op.type ?? "");
        if (type === "rect") {
            const x = number(op.x, 0);
            const y = number(op.y, 0);
            const w = number(op.w, 0);
            const h = number(op.h, 0);
            root.roundedPath(ctx, x, y, w, h, op.radius);
            if (op.color !== undefined) {
                ctx.fillStyle = String(op.color);
                ctx.fill();
            }
            if (number(op.border, 0) > 0) {
                ctx.lineWidth = number(op.border, 1);
                ctx.strokeStyle = String(op.borderColor ?? "#ffffff");
                ctx.stroke();
            }
        } else if (type === "circle") {
            const x = number(op.x, 0);
            const y = number(op.y, 0);
            const r = Math.max(0, number(op.r, 0));
            ctx.beginPath();
            ctx.arc(x, y, r, 0, Math.PI * 2);
            if (op.color !== undefined) {
                ctx.fillStyle = String(op.color);
                ctx.fill();
            }
            if (number(op.border, 0) > 0) {
                ctx.lineWidth = number(op.border, 1);
                ctx.strokeStyle = String(op.borderColor ?? "#ffffff");
                ctx.stroke();
            }
        } else if (type === "line") {
            ctx.beginPath();
            ctx.moveTo(number(op.x1, 0), number(op.y1, 0));
            ctx.lineTo(number(op.x2, 0), number(op.y2, 0));
            ctx.lineWidth = number(op.width, 1);
            ctx.strokeStyle = String(op.color ?? "#ffffff");
            ctx.lineCap = "round";
            ctx.stroke();
        } else if (type === "arc") {
            ctx.beginPath();
            ctx.arc(number(op.x, 0), number(op.y, 0), Math.max(0, number(op.r, 0)),
                number(op.from, 0), number(op.to, Math.PI * 2));
            ctx.lineWidth = number(op.width, 2);
            ctx.strokeStyle = String(op.color ?? "#ffffff");
            ctx.lineCap = "round";
            ctx.stroke();
        } else if (type === "text") {
            root.paintText(ctx, op);
        } else if (type === "image") {
            root.paintImage(ctx, op);
        }
    }
}
