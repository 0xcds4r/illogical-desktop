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

    function open(path) {
        Quickshell.execDetached([Directories.scriptPath + "/desktop-open.sh", path]);
    }

    function rename(from, to) {
        if (from === to || to.trim() === "")
            return;
        Quickshell.execDetached(["mv", "--", from, to]);
    }

    function trash(path) {
        Quickshell.execDetached(["gio", "trash", "--", path]);
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

    function compress(destination, parentDir, names) {
        const script = 'cd "$1" || exit 1; dest="$2"; shift 2; zip -r "$dest" -- "$@"';
        const args = ["bash", "-c", script, "compress", parentDir, destination];
        for (const name of names)
            args.push(name);
        Quickshell.execDetached(args);
    }

    function launchDesktopFile(path) {
        Quickshell.execDetached(["gio", "launch", path]);
    }
}
