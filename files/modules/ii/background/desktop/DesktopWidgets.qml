pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Desktop widget instances and their persisted state.
Singleton {
    id: root

    readonly property string stateDir: `${Quickshell.env("HOME")}/.local/state/quickshell/user`
    readonly property string filePath: `${root.stateDir}/desktop-widgets.json`
    readonly property string paintDir: `${root.stateDir}/desktop-widgets`
    readonly property string desktopFolderPath: {
        let folder = (DesktopConfig.folder ?? "").trim();
        if (folder.startsWith("file://"))
            folder = folder.substring(7);
        if (folder.startsWith("~/"))
            folder = Quickshell.env("HOME") + folder.substring(1);
        return folder === "" ? `${Quickshell.env("HOME")}/Desktop` : folder;
    }
    readonly property string customDir: root.desktopFolderPath + "/.widgets"
    readonly property string legacyCustomDir: `${Quickshell.env("HOME")}/.config/illogical-impulse/desktop-widgets`
    readonly property string customDirUrl: "file://" + root.customDir
    readonly property string luaRuntime: Quickshell.env("LUA") || "lua"
    readonly property string luaHostPath: String(Qt.resolvedUrl("lua/host.lua")).replace("file://", "")
    readonly property string examplePath: root.customDir + "/example.lua"
    readonly property string builtinDir: String(Qt.resolvedUrl("lua/widgets")).replace("file://", "")
    property string reloadId: ""
    property int reloadCounter: 0
    property bool ready: false

    property alias widgets: adapter.widgets

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.paintDir]);
        Quickshell.execDetached(["mkdir", "-p", root.customDir]);
        // Move scripts from the old location once, without overwriting anything.
        Quickshell.execDetached(["bash", "-c",
            `[ -d "$1" ] && for f in "$1"/*.lua; do [ -e "$f" ] && cp -n "$f" "$2"/; done; true`,
            "migrate-widgets", root.legacyCustomDir, root.customDir]);
    }

    Timer {
        id: writeTimer
        interval: 120
        repeat: false
        onTriggered: view.writeAdapter()
    }

    FileView {
        id: view
        path: root.filePath
        watchChanges: false
        onAdapterUpdated: writeTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeTimer.restart();
        }

        adapter: JsonAdapter {
            id: adapter
            property list<var> widgets: []
        }
    }

    function defaultSize(type, style) {
        if (type === "clock")
            return style === "analog" ? { width: 220, height: 220 }
                 : style === "minimal" ? { width: 280, height: 96 }
                 : { width: 300, height: 130 };
        if (type === "calendar")
            return style === "compact" ? { width: 280, height: 120 } : { width: 380, height: 320 };
        if (type === "datetime")
            return style === "inline" ? { width: 420, height: 90 } : { width: 320, height: 130 };
        if (type === "notes")
            return { width: 280, height: 240 };
        if (type === "timer")
            return style === "pill" ? { width: 380, height: 120 } : { width: 300, height: 330 };
        if (type === "paint")
            return { width: 380, height: 300 };
        if (type === "custom")
            return { width: 320, height: 220 };
        return { width: 300, height: 150 };
    }

    function addBuiltin(name, style) {
        const id = "w" + Date.now().toString(36) + Math.floor(Math.random() * 10000).toString(36);
        const size = root.defaultSize(name, style);
        const count = (root.widgets || []).length;
        const widget = {
            id: id,
            type: "custom",
            style: style,
            script: root.builtinDir + "/" + name + ".lua",
            x: 80 + (count % 4) * 430,
            y: 80 + Math.floor(count / 4) % 3 * 300,
            width: size.width,
            height: size.height,
            text: "",
            timerEnd: 0,
            timerRunning: false,
            timerDuration: 300000,
            paintPath: root.paintDir + "/" + id + ".png"
        };
        root.widgets = (root.widgets || []).concat([widget]);
    }

    function addCustom(script) {
        const id = "w" + Date.now().toString(36) + Math.floor(Math.random() * 10000).toString(36);
        const size = root.defaultSize("custom");
        const count = (root.widgets || []).length;
        const widget = {
            id: id,
            type: "custom",
            style: "custom",
            script: script,
            x: 80 + (count % 4) * 430,
            y: 80 + Math.floor(count / 4) % 3 * 300,
            width: size.width,
            height: size.height,
            text: "",
            timerEnd: 0,
            timerRunning: false,
            timerDuration: 300000,
            paintPath: root.paintDir + "/" + id + ".png"
        };
        root.widgets = (root.widgets || []).concat([widget]);
    }

    function createExample() {
        Quickshell.execDetached(["mkdir", "-p", root.customDir]);
        Quickshell.execDetached(["bash", "-c",
            `[ -f "$1" ] || cp "$2" "$1"`,
            "example", root.examplePath,
            String(Qt.resolvedUrl("lua/example.lua")).replace("file://", "")]);
    }

    function openCustomFolder() {
        Quickshell.execDetached(["mkdir", "-p", root.customDir]);
        Quickshell.execDetached(["xdg-open", root.customDir]);
    }

    function reloadWidget(id) {
        root.reloadId = id;
        root.reloadCounter += 1;
    }

    function add(type, style) {
        const id = "w" + Date.now().toString(36) + Math.floor(Math.random() * 10000).toString(36);
        const size = defaultSize(type, style);
        const count = (root.widgets || []).length;
        const widget = {
            id: id,
            type: type,
            style: style,
            x: 80 + (count % 4) * 430,
            y: 80 + Math.floor(count / 4) % 3 * 300,
            width: size.width,
            height: size.height,
            text: "",
            timerEnd: 0,
            timerRunning: false,
            timerDuration: 300000,
            paintPath: root.paintDir + "/" + id + ".png"
        };
        root.widgets = (root.widgets || []).concat([widget]);
    }

    function update(id, patch) {
        root.widgets = (root.widgets || []).map(widget =>
            widget.id === id ? Object.assign({}, widget, patch) : widget);
    }

    function remove(id) {
        root.widgets = (root.widgets || []).filter(widget => widget.id !== id);
    }

    function duplicate(id) {
        const source = (root.widgets || []).find(widget => widget.id === id);
        if (!source)
            return;
        const newId = "w" + Date.now().toString(36) + Math.floor(Math.random() * 10000).toString(36);
        const newPaintPath = root.paintDir + "/" + newId + ".png";
        const copy = Object.assign({}, source, {
            id: newId,
            x: source.x + 36,
            y: source.y + 36,
            paintPath: newPaintPath
        });
        if (source.type === "paint" && source.paintPath)
            Quickshell.execDetached(["cp", "-f", source.paintPath, newPaintPath]);
        if (source.type === "custom")
            Quickshell.execDetached(["bash", "-c",
                `[ -f "$1" ] && cp -f "$1" "$2" || true`,
                "state", root.paintDir + "/lua-state-" + source.id + ".lua",
                root.paintDir + "/lua-state-" + newId + ".lua"]);
        root.widgets = (root.widgets || []).concat([copy]);
    }

    function removeAll() {
        root.widgets = [];
    }
}
