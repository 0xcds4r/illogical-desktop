pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// In-memory cache of resolved desktop-entry names/icons and file-type icons.
// Keeps icons stable across FolderListModel reloads, so refreshing the desktop
// does not flash raw ".desktop" filenames or generic icons while async
// lookups re-run.
Singleton {
    id: root

    property var entries: ({})

    function get(path) {
        return root.entries[path] ?? null;
    }

    function store(path, data) {
        if (path === "")
            return;
        const map = Object.assign({}, root.entries);
        map[path] = Object.assign({}, map[path], data);
        root.entries = map;
    }

    function nameFor(path) {
        const entry = root.entries[path];
        return entry && entry.name !== undefined ? entry.name : "";
    }

    function iconFor(path) {
        const entry = root.entries[path];
        return entry && entry.icon !== undefined ? entry.icon : "";
    }

    function kindFor(path) {
        const entry = root.entries[path];
        return entry && entry.kind !== undefined ? entry.kind : "";
    }

    function valueFor(path) {
        const entry = root.entries[path];
        return entry && entry.value !== undefined ? entry.value : "";
    }

    function forget(path) {
        if (!root.entries[path])
            return;
        const map = Object.assign({}, root.entries);
        delete map[path];
        root.entries = map;
    }
}
