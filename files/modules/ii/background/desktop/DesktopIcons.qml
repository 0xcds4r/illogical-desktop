import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.desktop

// Windows-like desktop: icons for the contents of ~/Desktop, drag to move or
// drop into a folder, rubber-band and Ctrl selection, double-click to open,
// right-click for a context menu.
Item {
    id: root

    required property string screenName
    property var screenRef: null
    property color textColor: root.cfg.textColor
    readonly property color selectionColorValue: root.cfg.selectionColor
    readonly property color bandColorValue: root.cfg.bandColor

    function withAlpha(colorValue, alpha) {
        const color = Qt.color(colorValue);
        return Qt.rgba(color.r, color.g, color.b, Math.max(0, Math.min(1, alpha)));
    }

    function selectionFill(alpha) {
        return root.withAlpha(root.selectionColorValue, alpha);
    }

    function bandFill(alpha) {
        return root.withAlpha(root.bandColorValue, alpha);
    }

    readonly property var cfg: Config.options.background.desktopIcons
    readonly property int cellWidthValue: cfg.cellWidth
    readonly property int cellHeightValue: cfg.cellHeight
    readonly property int leftMargin: cfg.margin
    readonly property int topMargin: Appearance.sizes.barHeight + cfg.margin
    readonly property real zoomScale: cellWidthValue / 96
    readonly property string desktopFolder: Directories.home + "/Desktop"
    readonly property string desktopFolderPath: FileUtils.trimFileProtocol(root.desktopFolder)

    property var positions: ({})
    property var dragPositions: ({})
    property var selectedNames: ({})
    readonly property int selectedCount: Object.keys(selectedNames).length
    property string dropTargetName: ""

    // Workspace switch transition for the icon layer (layer-shell surfaces do not
    // get Hyprland's window animation).
    readonly property var hyprMonitor: Hyprland.monitorFor(root.screenRef)
    readonly property int activeWorkspaceId: root.hyprMonitor?.activeWorkspace?.id ?? 0
    property int previousWorkspaceId: 0
    property real switchOffset: 0
    property real switchOpacity: 1

    function windowCountForWorkspace(workspaceId) {
        const workspace = Hyprland.workspaces.values.find(candidate => candidate.id === workspaceId);
        return workspace ? workspace.toplevels.values.length : 0;
    }

    onActiveWorkspaceIdChanged: {
        const previousWorkspace = root.previousWorkspaceId;
        root.previousWorkspaceId = root.activeWorkspaceId;
        if (previousWorkspace === 0 || previousWorkspace === root.activeWorkspaceId)
            return;
        // Both workspaces are just the desktop: nothing to transition.
        if (root.windowCountForWorkspace(previousWorkspace) === 0 &&
            root.windowCountForWorkspace(root.activeWorkspaceId) === 0)
            return;
        const direction = root.activeWorkspaceId > previousWorkspace ? 1 : -1;
        root.switchOffset = direction * 48;
        root.switchOpacity = 0;
        workspaceSwitchAnim.restart();
    }

    ParallelAnimation {
        id: workspaceSwitchAnim
        NumberAnimation {
            target: root
            property: "switchOffset"
            to: 0
            duration: 300
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "switchOpacity"
            to: 1
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    // Rubber-band selection
    property bool banding: false
    property bool bandAdditive: false
    property real bandStartX: 0
    property real bandStartY: 0

    // Group drag
    property var dragGroupNames: []
    property var dragGroupBase: ({})

    property bool refreshAnimating: false
    property bool settingsOpen: false
    property string openWithPath: ""
    property real lastMenuX: 0
    property real lastMenuY: 0
    property string renamingPath: ""
    property string renamingName: ""
    property real renameX: 0
    property real renameY: 0

    anchors.fill: parent
    z: 5

    // The background surface takes keyboard focus on click (WlrKeyboardFocus.OnDemand),
    // so keep item focus here for Delete / Ctrl+C / Ctrl+V / F2 / F5.
    focus: true

    Component.onCompleted: root.loadPositions()

    Keys.onDeletePressed: root.trashSelected()
    Keys.onPressed: event => {
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_C) {
                root.copySelected();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_X) {
                root.cutSelected();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_V) {
                root.pasteClipboard();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_A) {
                root.selectAll();
                event.accepted = true;
                return;
            }
        }
        if (event.key === Qt.Key_Escape) {
            root.clearSelection();
            menu.close();
        } else if (event.key === Qt.Key_F2) {
            if (root.selectedCount === 1) {
                const name = Object.keys(root.selectedNames)[0];
                const path = root.pathForName(name);
                if (path !== "")
                    root.startRename(name, path);
            }
        } else if (event.key === Qt.Key_F5) {
            if (!event.isAutoRepeat)
                root.refresh();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root.loadPositions();
        }
    }

    FolderListModel {
        id: folderModel
        folder: root.desktopFolder
        showDirs: true
        showFiles: true
        showHidden: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        caseSensitive: false
    }

    // ---------------------------------------------------------------- layout

    function cellAt(index) {
        if (root.cfg.gridMode === "rows") {
            const usableWidth = Math.max(root.cellWidthValue, root.width - root.leftMargin * 2);
            const perRow = Math.max(1, Math.floor(usableWidth / root.cellWidthValue));
            return {
                x: root.leftMargin + (index % perRow) * root.cellWidthValue,
                y: root.topMargin + Math.floor(index / perRow) * root.cellHeightValue
            };
        }
        const usableHeight = Math.max(root.cellHeightValue, root.height - root.topMargin - root.leftMargin);
        const perColumn = Math.max(1, Math.floor(usableHeight / root.cellHeightValue));
        return {
            x: root.leftMargin + Math.floor(index / perColumn) * root.cellWidthValue,
            y: root.topMargin + (index % perColumn) * root.cellHeightValue
        };
    }

    function autoPosition(index) {
        return root.cellAt(index);
    }

    // Auto layout must not land on cells pinned by explicit positions, otherwise
    // newly added icons overlap with arranged ones.
    function autoPositionFor(name, index) {
        const pinned = Object.keys(root.positions);
        if (pinned.length === 0)
            return root.cellAt(index);

        const occupied = {};
        for (const other of pinned) {
            if (other === name)
                continue;
            const position = root.positions[other];
            occupied[root.cellKey(root.snapPosition(position.x, position.y))] = true;
        }

        let rank = 0;
        for (let i = 0; i < folderModel.count; i++) {
            const fileName = String(folderModel.get(i, "fileName"));
            if (fileName === name)
                break;
            if (!root.positions[fileName])
                rank++;
        }

        let free = 0;
        for (let i = 0; i < 500; i++) {
            const cell = root.cellAt(i);
            if (occupied[root.cellKey(cell)])
                continue;
            if (free === rank)
                return cell;
            free++;
        }
        return root.cellAt(index);
    }

    function cellKey(position) {
        const column = Math.round((position.x - root.leftMargin) / root.cellWidthValue);
        const row = Math.round((position.y - root.topMargin) / root.cellHeightValue);
        return `${column},${row}`;
    }

    function snapPosition(x, y) {
        const column = Math.max(0, Math.round((x - root.leftMargin) / root.cellWidthValue));
        const row = Math.max(0, Math.round((y - root.topMargin) / root.cellHeightValue));
        return {
            x: root.leftMargin + column * root.cellWidthValue,
            y: root.topMargin + row * root.cellHeightValue
        };
    }

    function iconXFor(name, index) {
        const dragged = root.dragPositions[name];
        if (dragged) return dragged.x;
        const saved = root.positions[name];
        if (saved) return saved.x;
        return root.autoPositionFor(name, index).x;
    }

    function iconYFor(name, index) {
        const dragged = root.dragPositions[name];
        if (dragged) return dragged.y;
        const saved = root.positions[name];
        if (saved) return saved.y;
        return root.autoPositionFor(name, index).y;
    }

    // ------------------------------------------------------------ selection

    function isNameSelected(name) {
        return root.selectedNames[name] === true;
    }

    function selectedNamesList() {
        return Object.keys(root.selectedNames);
    }

    function clearSelection() {
        root.selectedNames = ({});
    }

    function selectOnly(name) {
        const map = {};
        if (name !== "")
            map[name] = true;
        root.selectedNames = map;
    }

    function toggleNameSelection(name) {
        const map = Object.assign({}, root.selectedNames);
        if (map[name])
            delete map[name];
        else
            map[name] = true;
        root.selectedNames = map;
    }

    function selectAll() {
        const map = {};
        for (let i = 0; i < iconRepeater.count; i++) {
            const item = iconRepeater.itemAt(i);
            if (item)
                map[item.fileName] = true;
        }
        root.selectedNames = map;
    }

    function selectInRect(x, y, width, height, additive) {
        const map = additive ? Object.assign({}, root.selectedNames) : {};
        for (let i = 0; i < iconRepeater.count; i++) {
            const item = iconRepeater.itemAt(i);
            if (!item)
                continue;
            const intersects = item.x < x + width && item.x + item.width > x &&
                item.y < y + height && item.y + item.height > y;
            if (intersects)
                map[item.fileName] = true;
        }
        // Avoid re-evaluating every delegate binding on each mouse move.
        if (Object.keys(map).sort().join("\n") === Object.keys(root.selectedNames).sort().join("\n"))
            return;
        root.selectedNames = map;
    }

    function selectedPaths() {
        const paths = [];
        for (const name of root.selectedNamesList()) {
            const path = root.pathForName(name);
            if (path !== "")
                paths.push(path);
        }
        return paths;
    }

    // ------------------------------------------------------------ persistence

    function loadPositions() {
        if (!root.cfg.persistPositions) return;
        const list = Persistent.states.desktop?.iconPositions ?? [];
        const map = {};
        for (const entry of list) {
            const parts = String(entry).split("\t");
            if (parts.length === 4 && parts[0] === root.screenName)
                map[parts[1]] = { x: Number(parts[2]), y: Number(parts[3]) };
        }
        root.positions = map;
    }

    function savePositions() {
        if (!root.cfg.persistPositions) return;
        const existing = Persistent.states.desktop?.iconPositions ?? [];
        const others = existing.filter(entry => String(entry).split("\t")[0] !== root.screenName);
        const mine = Object.keys(root.positions).map(name =>
            `${root.screenName}\t${name}\t${Math.round(root.positions[name].x)}\t${Math.round(root.positions[name].y)}`);
        Persistent.states.desktop.iconPositions = others.concat(mine);
    }

    function removePosition(name) {
        if (!root.positions[name]) return;
        const map = Object.assign({}, root.positions);
        delete map[name];
        root.positions = map;
        root.savePositions();
    }

    // ------------------------------------------------------------ model utils

    function itemForName(name) {
        for (let i = 0; i < iconRepeater.count; i++) {
            const item = iconRepeater.itemAt(i);
            if (item && item.fileName === name)
                return item;
        }
        return null;
    }

    function pathForName(name) {
        for (let i = 0; i < folderModel.count; i++) {
            if (folderModel.get(i, "fileName") === name)
                return folderModel.get(i, "filePath");
        }
        return "";
    }

    function folderNameAt(pointerX, pointerY, excludedName) {
        for (let i = 0; i < iconRepeater.count; i++) {
            const item = iconRepeater.itemAt(i);
            if (!item || item.fileName === excludedName || !item.fileIsDir)
                continue;
            if (pointerX >= item.x && pointerX < item.x + item.width &&
                pointerY >= item.y && pointerY < item.y + item.height)
                return item.fileName;
        }
        return "";
    }

    function uniqueName(base) {
        const names = {};
        for (let i = 0; i < folderModel.count; i++)
            names[folderModel.get(i, "fileName")] = true;
        if (!names[base]) return base;
        let counter = 2;
        while (names[`${base} ${counter}`]) counter++;
        return `${base} ${counter}`;
    }

    property bool refreshCooldown: false

    Timer {
        id: refreshCooldownTimer
        interval: 200
        repeat: false
        onTriggered: root.refreshCooldown = false
    }

    function refresh() {
        if (root.refreshCooldown)
            return;
        root.refreshCooldown = true;
        refreshCooldownTimer.restart();
        root.refreshAnimating = true;
        refreshAnimTimer.restart();
        const current = root.desktopFolder;
        // Bounce through a non-existent path so FolderListModel reloads.
        folderModel.folder = "file:///nonexistent-desktop-refresh";
        folderModel.folder = current;
    }

    Timer {
        id: autoRefresh
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    function scheduleRefresh() {
        autoRefresh.restart();
    }

    Timer {
        id: refreshAnimTimer
        interval: 1000
        repeat: false
        onTriggered: root.refreshAnimating = false
    }

    function refreshWithAnimation() {
        root.refresh();
    }

    function openPath(path) {
        if (path.toLowerCase().endsWith(".desktop"))
            DesktopFileOps.launchDesktopFile(path);
        else
            DesktopFileOps.open(path);
    }

    function cellIndexFor(column, row) {
        if (root.cfg.gridMode === "rows") {
            const usableWidth = Math.max(root.cellWidthValue, root.width - root.leftMargin * 2);
            const perRow = Math.max(1, Math.floor(usableWidth / root.cellWidthValue));
            return row * perRow + column;
        }
        const usableHeight = Math.max(root.cellHeightValue, root.height - root.topMargin - root.leftMargin);
        const perColumn = Math.max(1, Math.floor(usableHeight / root.cellHeightValue));
        return column * perColumn + row;
    }

    function findFreeCell(position, occupied) {
        const column = Math.max(0, Math.round((position.x - root.leftMargin) / root.cellWidthValue));
        const row = Math.max(0, Math.round((position.y - root.topMargin) / root.cellHeightValue));
        const start = Math.max(0, root.cellIndexFor(column, row));
        for (let index = start; index < start + 800; index++) {
            const cell = root.cellAt(index);
            if (!occupied[root.cellKey(cell)])
                return cell;
        }
        return root.cellAt(start);
    }

    // Re-align explicit positions to the current cell size. Used after zooming or
    // changing cell dimensions, so snapping never produces overlaps.
    function resnapPositions() {
        if (!root.cfg.snapToGrid)
            return;
        const pinnedNames = Object.keys(root.positions);
        if (pinnedNames.length === 0)
            return;

        const occupied = {};
        const next = {};
        const ordered = [];
        for (let i = 0; i < folderModel.count; i++) {
            const name = String(folderModel.get(i, "fileName"));
            if (root.positions[name])
                ordered.push(name);
        }
        for (const name of pinnedNames) {
            if (!ordered.includes(name))
                ordered.push(name);
        }

        for (const name of ordered) {
            const cell = root.findFreeCell(
                root.snapPosition(root.positions[name].x, root.positions[name].y), occupied);
            next[name] = cell;
            occupied[root.cellKey(cell)] = true;
        }

        root.positions = next;
        root.savePositions();
    }

    function setZoom(cellWidth) {
        const previousWidth = root.cellWidthValue;
        const previousHeight = root.cellHeightValue;
        const width = Math.max(64, Math.min(220, Math.round(cellWidth)));
        if (width === previousWidth)
            return;
        const height = Math.max(64, Math.min(240, Math.round(previousHeight * width / previousWidth)));
        root.cfg.cellWidth = width;
        root.cfg.cellHeight = height;
        root.resnapPositions();
    }

    // ------------------------------------------------------------- clipboard

    function copySelected() {
        const paths = root.selectedPaths();
        if (paths.length > 0)
            DesktopFileOps.copy(paths);
    }

    function cutSelected() {
        const paths = root.selectedPaths();
        if (paths.length > 0)
            DesktopFileOps.cut(paths);
    }

    function uniqueCopyName(fileName) {
        const existing = {};
        for (let i = 0; i < folderModel.count; i++)
            existing[folderModel.get(i, "fileName")] = true;

        const dot = fileName.lastIndexOf(".");
        const base = dot > 0 ? fileName.substring(0, dot) : fileName;
        const extension = dot > 0 ? fileName.substring(dot) : "";
        let candidate = `${base} (copy)${extension}`;
        let counter = 2;
        while (existing[candidate]) {
            candidate = `${base} (copy ${counter})${extension}`;
            counter++;
        }
        return candidate;
    }

    function pasteClipboard() {
        const paths = DesktopFileOps.clipboard;
        if (paths.length === 0)
            return;
        if (DesktopFileOps.clipboardCut) {
            DesktopFileOps.moveInto(paths, root.desktopFolderPath);
        } else {
            for (const path of paths) {
                const name = path.substring(path.lastIndexOf("/") + 1);
                DesktopFileOps.copyTo(path, `${root.desktopFolderPath}/${root.uniqueCopyName(name)}`);
            }
        }
        root.scheduleRefresh();
    }

    function trashSelected() {
        const names = root.selectedNamesList();
        if (names.length === 0)
            return;
        root.clearSelection();
        for (const name of names) {
            const path = root.pathForName(name);
            if (path === "")
                continue;
            root.removePosition(name);
            DesktopFileOps.trash(path);
        }
        root.scheduleRefresh();
    }

    // ------------------------------------------------------------------ drag

    function beginDrag(name) {
        let names;
        if (root.isNameSelected(name)) {
            names = root.selectedNamesList();
        } else {
            root.selectOnly(name);
            names = [name];
        }
        const base = {};
        for (const selected of names) {
            const item = root.itemForName(selected);
            const index = item ? item.iconIndex : 0;
            base[selected] = { x: root.iconXFor(selected, index), y: root.iconYFor(selected, index) };
        }
        root.dragGroupNames = names;
        root.dragGroupBase = base;
    }

    function updateDrag(name, targetX, targetY, pointerX, pointerY) {
        if (!root.dragGroupBase[name])
            root.beginDrag(name);
        const anchor = root.dragGroupBase[name];
        if (!anchor)
            return;
        const dx = targetX - anchor.x;
        const dy = targetY - anchor.y;
        const map = {};
        for (const selected of root.dragGroupNames) {
            const base = root.dragGroupBase[selected];
            if (!base)
                continue;
            map[selected] = { x: base.x + dx, y: base.y + dy };
        }
        root.dragPositions = map;
        root.dropTargetName = root.folderNameAt(pointerX, pointerY, name);
    }

    function finishDrag(name, path, pointerX, pointerY) {
        const names = root.dragGroupNames.length > 0 ? root.dragGroupNames : [name];
        const moved = root.dragPositions;
        const origins = root.dragGroupBase;
        const target = (pointerX >= 0 && pointerY >= 0) ? root.folderNameAt(pointerX, pointerY, name) : "";

        root.dragPositions = ({});
        root.dragGroupNames = [];
        root.dragGroupBase = ({});
        root.dropTargetName = "";

        if (target !== "") {
            const targetPath = root.pathForName(target);
            if (targetPath !== "") {
                const paths = [];
                for (const selected of names) {
                    const selectedPath = root.pathForName(selected);
                    if (selectedPath === "" || selectedPath === targetPath)
                        continue;
                    // Never move a folder into itself or its own subtree.
                    if (targetPath.startsWith(selectedPath + "/"))
                        continue;
                    paths.push(selectedPath);
                }
                if (paths.length > 0)
                    DesktopFileOps.moveInto(paths, targetPath);
                for (const selected of names)
                    root.removePosition(selected);
            }
            root.scheduleRefresh();
            return;
        }

        if (pointerX >= 0 && !root.cfg.autoArrange)
            root.applyDropPositions(names, moved, origins);
    }

    function applyDropPositions(names, moved, origins) {
        const saved = Object.assign({}, root.positions);

        if (!root.cfg.snapToGrid) {
            for (const selected of names) {
                const position = moved[selected];
                if (!position)
                    continue;
                saved[selected] = { x: Math.max(0, position.x), y: Math.max(0, position.y) };
            }
            root.positions = saved;
            root.savePositions();
            return;
        }

        const dragged = {};
        for (const selected of names)
            dragged[selected] = true;

        // Occupied cells of everything that is not being dragged.
        const occupied = {};
        for (let i = 0; i < folderModel.count; i++) {
            const fileName = String(folderModel.get(i, "fileName"));
            if (dragged[fileName])
                continue;
            const item = root.itemForName(fileName);
            const index = item ? item.iconIndex : i;
            const position = saved[fileName] ?? root.autoPositionFor(fileName, index);
            occupied[root.cellKey(root.snapPosition(position.x, position.y))] = fileName;
        }

        for (const selected of names) {
            const position = moved[selected];
            if (!position)
                continue;
            const target = root.snapPosition(position.x, position.y);
            const targetKey = root.cellKey(target);
            const occupant = occupied[targetKey];
            const origin = origins[selected];
            const originSnapped = origin ? root.snapPosition(origin.x, origin.y) : null;

            saved[selected] = target;

            // Snap to grid never allows two icons in one cell: swap instead.
            if (occupant && occupant !== selected && originSnapped) {
                saved[occupant] = originSnapped;
                delete occupied[targetKey];
                occupied[root.cellKey(originSnapped)] = occupant;
            }
            occupied[targetKey] = selected;
        }

        root.positions = saved;
        root.savePositions();
    }

    // --------------------------------------------------------------- actions

    function createFolder() {
        const name = root.uniqueName(Translation.tr("New Folder"));
        const path = `${root.desktopFolderPath}/${name}`;
        DesktopFileOps.newFolder(root.desktopFolderPath, name);
        pendingRenameTimer.pendingPath = path;
        pendingRenameTimer.pendingName = name;
        pendingRenameTimer.restart();
        root.scheduleRefresh();
    }

    function createFile() {
        const name = root.uniqueName(Translation.tr("New File"));
        const path = `${root.desktopFolderPath}/${name}`;
        DesktopFileOps.newFile(root.desktopFolderPath, name);
        pendingRenameTimer.pendingPath = path;
        pendingRenameTimer.pendingName = name;
        pendingRenameTimer.restart();
        root.scheduleRefresh();
    }

    Timer {
        id: pendingRenameTimer
        interval: 350
        repeat: false
        property string pendingPath: ""
        property string pendingName: ""
        onTriggered: {
            if (pendingPath === "") return;
            const path = pendingPath;
            const name = pendingName;
            pendingPath = "";
            pendingName = "";
            root.startRename(name, path);
        }
    }

    function startRename(name, path) {
        const item = root.itemForName(name);
        let x = root.width / 2 - 120;
        let y = root.height / 2 - 20;
        if (item) {
            const point = item.mapToItem(root, 0, 0);
            x = point.x;
            y = point.y + 20;
        }
        root.renameX = Math.max(8, Math.min(x, root.width - 248));
        root.renameY = Math.max(8, Math.min(y, root.height - 56));
        root.renamingName = name;
        root.renamingPath = path;
        root.selectOnly(name);
    }

    function cancelRename() {
        root.renamingPath = "";
        root.renamingName = "";
    }

    function commitRename(newName) {
        const oldPath = root.renamingPath;
        const oldName = root.renamingName;
        const trimmed = String(newName).trim();
        root.renamingPath = "";
        root.renamingName = "";
        if (oldPath === "" || trimmed === "" || trimmed === oldName || trimmed.indexOf("/") !== -1)
            return;
        DesktopFileOps.rename(oldPath, `${root.desktopFolderPath}/${trimmed}`);
        root.scheduleRefresh();
        if (root.positions[oldName]) {
            const map = Object.assign({}, root.positions);
            map[trimmed] = map[oldName];
            delete map[oldName];
            root.positions = map;
            root.savePositions();
        }
        if (root.isNameSelected(oldName)) {
            const map = Object.assign({}, root.selectedNames);
            delete map[oldName];
            map[trimmed] = true;
            root.selectedNames = map;
        }
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function openTerminal() {
        Quickshell.execDetached(["bash", "-c",
            `cd ${root.shellQuote(root.desktopFolderPath)} && ${Config.options.apps.terminal}`]);
    }

    // ----------------------------------------------------------------- menus

    Process {
        id: openWithProcess
        running: false
        command: [Directories.scriptPath + "/desktop-open-with.sh", root.openWithPath]
        stdout: StdioCollector {
            onStreamFinished: root.showOpenWith(text)
        }
    }

    function openWith(name, path) {
        root.openWithPath = path;
        openWithProcess.running = false;
        openWithProcess.running = true;
    }

    function showOpenWith(output) {
        const targetPath = root.openWithPath;
        const items = [
            { label: Translation.tr("Open with"), icon: "open_in_new", enabled: false },
            { separator: true }
        ];
        for (const line of String(output).split("\n")) {
            if (line.trim() === "")
                continue;
            const parts = line.split("\t");
            if (parts.length < 4)
                continue;
            const id = parts[0];
            const appName = parts[1];
            const icon = parts[2];
            const desktopFile = parts[3];
            const iconSource = icon === ""
                ? Quickshell.iconPath("application-x-executable", "application-x-executable")
                : icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, "application-x-executable");
            items.push({
                label: appName !== "" ? appName : id,
                iconSource: iconSource,
                action: () => Quickshell.execDetached(["gio", "launch", desktopFile, targetPath])
            });
        }
        if (items.length === 2)
            items.push({ label: Translation.tr("No applications found"), icon: "error", enabled: false });
        menu.openAt(root.lastMenuX, root.lastMenuY, items);
    }

    function iconMenu(name, path) {
        const multiple = root.selectedCount > 1;
        const paths = multiple ? root.selectedPaths() : [path];
        return [
            { label: Translation.tr("Open"), icon: "open_in_new", action: () => {
                for (const target of paths)
                    root.openPath(target);
            } },
            { label: Translation.tr("Open with"), icon: "apps", enabled: !multiple,
              action: () => root.openWith(name, path) },
            { separator: true },
            { label: Translation.tr("Rename"), icon: "edit", enabled: !multiple,
              action: () => root.startRename(name, path) },
            { label: Translation.tr("Copy"), icon: "content_copy",
              action: () => DesktopFileOps.copy(paths) },
            { label: Translation.tr("Cut"), icon: "content_cut",
              action: () => DesktopFileOps.cut(paths) },
            { separator: true },
            { label: Translation.tr("Move to Trash"), icon: "delete", action: () => root.trashSelected() }
        ];
    }

    function resetPositions() {
        root.positions = ({});
        root.savePositions();
    }

    function toggleAutoArrange() {
        root.cfg.autoArrange = !root.cfg.autoArrange;
        if (root.cfg.autoArrange)
            root.resetPositions();
    }

    function toggleGridMode() {
        root.cfg.gridMode = root.cfg.gridMode === "columns" ? "rows" : "columns";
        root.resetPositions();
    }

    function toggleSnapToGrid() {
        root.cfg.snapToGrid = !root.cfg.snapToGrid;
        if (root.cfg.snapToGrid)
            root.resnapPositions();
    }

    function openArrangeMenu() {
        const items = [
            { label: Translation.tr("Arrange icons"), icon: "grid_view", enabled: false },
            { separator: true },
            { label: Translation.tr("By name (A-Z)"), icon: "sort_by_alpha", action: () => root.arrangeIcons("name") },
            { label: Translation.tr("By type"), icon: "category", action: () => root.arrangeIcons("type") },
            { label: Translation.tr("By size"), icon: "data_usage", action: () => root.arrangeIcons("size") },
            { label: Translation.tr("By date modified"), icon: "schedule", action: () => root.arrangeIcons("date") },
            { separator: true },
            { label: root.cfg.autoArrange ? Translation.tr("Auto arrange: on") : Translation.tr("Auto arrange: off"),
              icon: "grid_on", action: () => root.toggleAutoArrange() },
            { label: root.cfg.gridMode === "columns" ? Translation.tr("Grid: columns") : Translation.tr("Grid: rows"),
              icon: "view_column", action: () => root.toggleGridMode() },
            { label: root.cfg.snapToGrid ? Translation.tr("Snap to grid: on") : Translation.tr("Snap to grid: off"),
              icon: "grid_4x4", action: () => root.toggleSnapToGrid() },
            { label: Translation.tr("Reset positions"), icon: "restart_alt", action: () => root.resetPositions() }
        ];
        menu.openAt(root.lastMenuX, root.lastMenuY, items);
    }

    function arrangeIcons(mode) {
        const entries = [];
        for (let i = 0; i < folderModel.count; i++) {
            entries.push({
                name: String(folderModel.get(i, "fileName")),
                isDir: Boolean(folderModel.get(i, "fileIsDir")),
                size: Number(folderModel.get(i, "fileSize") ?? 0),
                modified: Number(folderModel.get(i, "fileModified") ?? 0)
            });
        }
        const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" });
        entries.sort((a, b) => {
            if (a.isDir !== b.isDir)
                return a.isDir ? -1 : 1;
            if (mode === "type") {
                const ea = a.name.includes(".") ? a.name.split(".").pop().toLowerCase() : "";
                const eb = b.name.includes(".") ? b.name.split(".").pop().toLowerCase() : "";
                if (ea !== eb)
                    return ea.localeCompare(eb);
                return byName(a, b);
            }
            if (mode === "size")
                return (a.size - b.size) || byName(a, b);
            if (mode === "date")
                return (a.modified - b.modified) || byName(a, b);
            return byName(a, b);
        });
        const map = {};
        entries.forEach((entry, index) => {
            map[entry.name] = root.autoPosition(index);
        });
        root.positions = map;
        root.savePositions();
    }

    function desktopMenu() {
        return [
            { label: Translation.tr("New Folder"), icon: "create_new_folder", action: () => root.createFolder() },
            { label: Translation.tr("New File"), icon: "note_add", action: () => root.createFile() },
            { label: Translation.tr("Paste"), icon: "content_paste", enabled: DesktopFileOps.canPaste(),
              action: () => root.pasteClipboard() },
            { separator: true },
            { label: Translation.tr("Select all"), icon: "select_all", action: () => root.selectAll() },
            { label: Translation.tr("Arrange icons"), icon: "grid_view", action: () => root.openArrangeMenu() },
            { label: Translation.tr("Refresh"), icon: "refresh", action: () => root.refreshWithAnimation() },
            { separator: true },
            { label: Translation.tr("Desktop settings"), icon: "settings", action: () => root.settingsOpen = true },
            { label: Translation.tr("Open terminal"), icon: "terminal", action: () => root.openTerminal() }
        ];
    }

    // ------------------------------------------------------------ background

    MouseArea {
        id: backgroundArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: event => {
            root.forceActiveFocus();
            menu.close();
            if (event.button === Qt.RightButton) {
                root.clearSelection();
                root.lastMenuX = event.x;
                root.lastMenuY = event.y;
                menu.openAt(event.x, event.y, root.desktopMenu());
                return;
            }
            const additive = (event.modifiers & Qt.ControlModifier) !== 0;
            if (!additive)
                root.clearSelection();
            root.banding = true;
            root.bandAdditive = additive;
            root.bandStartX = event.x;
            root.bandStartY = event.y;
            bandRect.visible = false;
        }

        onPositionChanged: event => {
            if (!root.banding || !(event.buttons & Qt.LeftButton))
                return;
            const x = Math.min(root.bandStartX, event.x);
            const y = Math.min(root.bandStartY, event.y);
            const width = Math.abs(event.x - root.bandStartX);
            const height = Math.abs(event.y - root.bandStartY);
            if (width < 3 && height < 3)
                return;
            bandRect.x = x;
            bandRect.y = y;
            bandRect.width = width;
            bandRect.height = height;
            bandRect.visible = true;
            root.selectInRect(x, y, width, height, root.bandAdditive);
        }

        onReleased: {
            root.banding = false;
            bandRect.visible = false;
        }

        onCanceled: {
            root.banding = false;
            bandRect.visible = false;
        }
    }

    Rectangle {
        id: bandRect
        visible: false
        x: 0
        y: 0
        width: 0
        height: 0
        z: 3000
        color: root.bandFill(root.cfg.bandOpacity)
        border.width: 1
        border.color: root.bandFill(Math.min(1, root.cfg.bandOpacity * 3))
    }

    Item {
        id: iconsContainer
        anchors.fill: parent
        visible: root.cfg.enable
        opacity: root.switchOpacity
        transform: Translate {
            x: root.switchOffset
        }

    Repeater {
        id: iconRepeater
        model: folderModel

        delegate: DesktopIcon {
            container: root
            iconIndex: index
            appearDelay: root.refreshAnimating ? Math.min(index * 22, 400) : 0
            fileName: model.fileName
            filePath: model.filePath
            fileURL: model.fileUrl
            fileIsDir: model.fileIsDir
            textColor: root.textColor
            isSelected: root.isNameSelected(model.fileName)
            isDropTarget: root.dropTargetName === model.fileName

            onPicked: ctrl => {
                if (ctrl)
                    root.toggleNameSelection(model.fileName);
                else if (!root.isNameSelected(model.fileName))
                    root.selectOnly(model.fileName);
                root.forceActiveFocus();
                menu.close();
            }
            onOpenRequested: root.openPath(model.filePath)
            onContextRequested: (x, y) => {
                if (!root.isNameSelected(model.fileName))
                    root.selectOnly(model.fileName);
                root.lastMenuX = x;
                root.lastMenuY = y;
                menu.openAt(x, y, root.iconMenu(model.fileName, model.filePath));
            }
            onDragStarted: root.beginDrag(model.fileName)
            onDragMoved: (targetX, targetY, pointerX, pointerY) =>
                root.updateDrag(model.fileName, targetX, targetY, pointerX, pointerY)
            onDragFinished: (pointerX, pointerY) =>
                root.finishDrag(model.fileName, model.filePath, pointerX, pointerY)
        }
    }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        z: 4000
        onWheel: event => {
            if (!(event.modifiers & Qt.ControlModifier))
                return;
            root.setZoom(root.cellWidthValue + (event.angleDelta.y >= 0 ? 8 : -8));
            event.accepted = true;
        }
    }

    DesktopContextMenu {
        id: menu
    }

    Loader {
        id: settingsLoader
        active: root.settingsOpen

        sourceComponent: DesktopSettings {
            desktop: root
            onDismissed: root.settingsOpen = false
        }
    }

    // ---------------------------------------------------------------- rename

    Loader {
        id: renameLoader
        active: root.renamingPath !== ""

        sourceComponent: PanelWindow {
            visible: true
            screen: root.screenRef
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:desktop-rename"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.cancelRename()
            }

            Rectangle {
                x: root.renameX
                y: root.renameY
                width: 240
                height: 40
                radius: Appearance.rounding.verysmall
                color: Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.colors.colPrimary

                TextInput {
                    id: renameInput
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.renamingName
                    color: Appearance.colors.colOnLayer1
                    selectionColor: Appearance.colors.colPrimary
                    selectedTextColor: Appearance.colors.colOnPrimary
                    font.pixelSize: Appearance.font.pixelSize.normal
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    focus: true

                    onAccepted: root.commitRename(text)
                    Keys.onEscapePressed: root.cancelRename()

                    Component.onCompleted: {
                        forceActiveFocus();
                        selectAll();
                    }
                }
            }
        }
    }
}
