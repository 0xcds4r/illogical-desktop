pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

// File operations for the desktop icon grid.
// All commands use argument arrays, never a shell string, so file names with
// spaces or quotes are safe.
Singleton {
    id: root

    property list<string> clipboard: []
    property bool clipboardCut: false

    readonly property string helperPath: Directories.scriptPath + "/desktop-helper"

    function open(path) {
        Quickshell.execDetached([root.helperPath, "open", path]);
    }

    function rename(from, to) {
        if (from === to || to.trim() === "")
            return;
        Quickshell.execDetached(["mv", "--", from, to]);
    }

    function trash(paths) {
        const args = [root.helperPath, "trash", "move"];
        for (const path of paths)
            args.push(path);
        Quickshell.execDetached(args);
    }

    function restoreTrash(paths) {
        const args = [root.helperPath, "trash", "restore"];
        for (const path of paths)
            args.push(path);
        Quickshell.execDetached(args);
    }

    function openTrash() {
        Quickshell.execDetached([root.helperPath, "open-trash"]);
    }

    function emptyTrash() {
        Quickshell.execDetached([root.helperPath, "trash", "empty"]);
    }

    function copy(paths) {
        root.clipboard = paths;
        root.clipboardCut = false;
    }

    function cut(paths) {
        root.clipboard = paths;
        root.clipboardCut = true;
    }

    function canPaste() {
        return root.clipboard.length > 0;
    }

    function paste(destDir) {
        if (root.clipboard.length === 0)
            return;
        const args = [root.clipboardCut ? "mv" : "cp", "-r", "-n", "--"];
        for (const path of root.clipboard)
            args.push(path);
        args.push(destDir);
        Quickshell.execDetached(args);
        if (root.clipboardCut)
            root.clipboard = [];
    }

    function copyTo(source, destination) {
        Quickshell.execDetached(["cp", "-r", "--", source, destination]);
    }

    function moveInto(paths, destDir) {
        const args = ["mv", "-n", "--"];
        for (const path of paths)
            args.push(path);
        args.push(destDir);
        Quickshell.execDetached(args);
    }

    function newFolder(parentDir, name) {
        Quickshell.execDetached(["mkdir", "--", `${parentDir}/${name}`]);
    }

    function newFile(parentDir, name) {
        Quickshell.execDetached(["touch", "--", `${parentDir}/${name}`]);
    }

    function createLink(source, destination) {
        Quickshell.execDetached(["ln", "-s", "--", source, destination]);
    }

    function compress(destination, parentDir, names, format, level) {
        const args = [root.helperPath, "compress", destination, parentDir, format, String(level)];
        for (const name of names)
            args.push(name);
        Quickshell.execDetached(args);
    }

    function launchDesktopFile(path) {
        Quickshell.execDetached(["gio", "launch", path]);
    }
}
