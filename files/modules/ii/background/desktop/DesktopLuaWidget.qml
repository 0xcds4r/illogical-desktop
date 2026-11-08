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
    property var inputs: ({})
    property var lastSent: ({})
    property int tickInterval: 0
    property real luaRotation: 0
    property string errorText: ""
    property bool started: false

    rotation: root.luaRotation

    function send(line) {
        if (proc.running)
            proc.write(line + "\n");
    }

    function actionText(action) {
        return String(action.title ?? "") + "\n" + String(action.body ?? "");
    }

    function runAction(action) {
        switch (String(action.type ?? "")) {
        case "notify": {
            const parts = actionText(action).split("\n");
            Quickshell.execDetached(["notify-send", parts[0] || "Desktop", parts.slice(1).join("\n")]);
            break;
        }
        case "spawn": {
            const command = action.command ?? [];
            if (command.length > 0)
                Quickshell.execDetached(command);
            break;
        }
        case "open":
            if (action.path)
                Quickshell.execDetached(["xdg-open", String(action.path)]);
            break;
        }
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
            root.luaRotation = Number(meta.rotation ?? 0);
            root.cursorShape = String(meta.cursor ?? "pointing");
            if (width > 0 && height > 0
                    && (Math.abs(width - (root.widgetData.width ?? 0)) > 1
                        || Math.abs(height - (root.widgetData.height ?? 0)) > 1))
                DesktopWidgets.update(root.widgetData.id, { width: width, height: height });
        }
        if (message.actions) {
            for (const action of message.actions)
                root.runAction(action);
        }
        root.errorText = message.error ? String(message.error) : "";
        root.ops = message.ops ?? [];
        canvas.requestPaint();
    }

    function buttonName(button) {
        if (button === Qt.RightButton)
            return "right";
        if (button === Qt.MiddleButton)
            return "middle";
        return "left";
    }

    function cursorFor(name) {
        switch (name) {
        case "arrow": return Qt.ArrowCursor;
        case "cross": return Qt.CrossCursor;
        case "text": return Qt.IBeamCursor;
        case "hand": return Qt.OpenHandCursor;
        default: return Qt.PointingHandCursor;
        }
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

    function sendStrings() {
        const dictionary = DesktopTranslation.dictionary();
        for (const key in dictionary)
            root.send("s\t" + encodeURIComponent(key) + "\t" + encodeURIComponent(String(dictionary[key])));
        // Repaint once so labels picked up via desktop.tr() show translated.
        root.send("t\t" + Date.now());
    }

    function sendInput(key, text) {
        root.lastSent[key] = text;
        root.send("e\t" + key + "\t" + encodeURIComponent(text));
    }

    function ensureInput(op) {
        const key = String(op.key ?? "default");
        let editor = root.inputs[key];
        if (!editor) {
            const multiline = op.multiline !== false;
            editor = Qt.createQmlObject(multiline
                ? "import QtQuick; TextEdit { selectByMouse: true; persistentSelection: true; wrapMode: TextEdit.Wrap }"
                : "import QtQuick; TextInput { selectByMouse: true }", root, "luaInput");
            editor.textChanged.connect(() => root.sendInput(key, editor.text));
            editor.activeFocusChanged.connect(() => {
                if (!editor.activeFocus)
                    root.sendInput(key, editor.text);
            });
            const map = Object.assign({}, root.inputs);
            map[key] = editor;
            root.inputs = map;
            root.lastSent[key] = "";
        }

        editor.x = root.number(op.x, 0);
        editor.y = root.number(op.y, 0);
        editor.width = Math.max(0, root.number(op.w, 0));
        editor.height = Math.max(0, root.number(op.h, 0));
        editor.visible = op.hidden !== true;
        editor.color = String(op.color ?? "#ffffff");
        editor.font.pixelSize = root.number(op.size, 14);
        editor.font.family = String(op.family ?? "sans-serif");
        editor.horizontalAlignment = op.align === "center" ? TextInput.AlignHCenter : TextInput.AlignLeft;
        editor.selectionColor = String(op.selectionColor ?? "#4A90D9");
        editor.selectedTextColor = String(op.selectedTextColor ?? "#ffffff");

        const next = String(op.text ?? "");
        // Never overwrite the editor while the user is typing in it.
        if (!editor.activeFocus && next !== editor.text)
            editor.text = next;
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
                console.log("lua widget " + (root.widgetData.id ?? "") + ":", data);
            }
        }

        onRunningChanged: {
            if (!proc.running)
                return;
            root.started = true;
            root.send("i\t" + root.width + "\t" + root.height + "\t"
                + (root.widgetData.style ?? "") + "\t" + (root.widgetData.id ?? ""));
            root.sendStrings();
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.log("lua widget exited:", exitCode);
            canvas.requestPaint();
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

    Keys.onPressed: event => {
        if (event.isAutoRepeat) {
            event.accepted = true;
            return;
        }
        root.send("k\t" + root.keyName(event) + "\t" + root.modifiers(event.modifiers));
        event.accepted = true;
    }

    Keys.onReleased: event => {
        if (event.isAutoRepeat)
            return;
        root.send("u\t" + root.keyName(event) + "\t" + root.modifiers(event.modifiers));
    }

    onActiveFocusChanged: {
        if (!activeFocus)
            root.send("b");
    }

    function keyName(event) {
        switch (event.key) {
        case Qt.Key_Left: return "left";
        case Qt.Key_Right: return "right";
        case Qt.Key_Up: return "up";
        case Qt.Key_Down: return "down";
        case Qt.Key_Space: return "space";
        case Qt.Key_Return: return "enter";
        case Qt.Key_Enter: return "enter";
        case Qt.Key_Escape: return "escape";
        case Qt.Key_Tab: return "tab";
        case Qt.Key_Backspace: return "backspace";
        case Qt.Key_Delete: return "delete";
        case Qt.Key_Home: return "home";
        case Qt.Key_End: return "end";
        case Qt.Key_PageUp: return "pageup";
        case Qt.Key_PageDown: return "pagedown";
        }
        const text = event.text;
        if (text && text.length === 1)
            return text.toLowerCase();
        return "key_" + event.key;
    }

    function modifiers(mask) {
        const parts = [];
        if (mask & Qt.ControlModifier)
            parts.push("ctrl");
        if (mask & Qt.AltModifier)
            parts.push("alt");
        if (mask & Qt.ShiftModifier)
            parts.push("shift");
        if (mask & Qt.MetaModifier)
            parts.push("meta");
        return parts.join("+");
    }

    MouseArea {
        id: input
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: root.cursorFor(root.cursorShape ?? "pointing")

        onPressed: mouse => {
            root.forceActiveFocus();
            root.send("p\t" + Math.round(mouse.x) + "\t" + Math.round(mouse.y)
                + "\t" + root.buttonName(mouse.button));
        }
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

    property string cursorShape: "pointing"

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
        const weight = op.weight !== undefined ? String(op.weight) + " " : "";
        ctx.font = weight + number(op.size, 14) + "px " + String(op.font ?? "sans-serif");
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
            ctx.lineCap = String(op.lineCap ?? "round");
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
        } else if (type === "input") {
            root.ensureInput(op);
        }
    }
}
