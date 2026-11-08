# illogical-desktop

A Windows-like active desktop for **illogical-impulse** (quickshell `ii`) on Hyprland:
icons for `~/Desktop`, selection, drag & drop, context menus, file operations and
desktop-entry aware icons/launching.

<p align="center"><img src="assets/screenshot.jpg" width="100%" alt="Desktop with icons"></p>

## Features

- Icons for everything in `~/Desktop`, laid out on a grid (columns or rows).
- Single click selects, double click opens with the system default application.
- Selection:
  - rubber-band selection (blue rectangle, color/opacity configurable);
  - `Ctrl+Click` / `Ctrl+RightClick` toggles, `Shift+Click` selects a range;
  - arrow keys move the selection, `Home`/`End`, `Enter` opens, `Space` previews;
  - `Ctrl+A` selects all, `Esc` clears;
  - group drag moves the whole selection;
  - group actions: `Delete`, `Ctrl+C`, `Ctrl+X`, `Ctrl+V`, context menu.
- `Ctrl+Z` undoes the last delete (restores from trash), rename or move.
- Drag an icon onto a folder to move it there (with groups); `Ctrl+drag` copies instead.
- `Snap to grid`: dropped icons align to cells and swap with the occupant instead of
  overlapping.
- `Ctrl+wheel` zooms the grid; snapped positions are re-aligned to the new cell size,
  with overlaps resolved to free cells. Changing cell size or margin in the settings
  modal behaves the same way.
- Context menu on icons: Open, Open with, Rename, Copy, Cut, Create link, Compress,
  Move to Trash, Properties.
- Context menu on the desktop: New Folder, New File, Paste, Select all, Arrange icons,
  Refresh, Desktop settings, Open terminal.
- Menus size themselves to the longest label, so longer translations are never cut off.
- Arrange: by name, by type, by size, by date modified; auto arrange; grid direction;
  snap to grid; reset positions.
- Clipboard: `Ctrl+C` / `Ctrl+X` / `Ctrl+V` (copies get `name (copy).ext`).
- **Create link** makes a symlink (`name (link).ext`); **Compress** offers ZIP
  (fast/normal/max) and tar.gz; **Properties** shows type, MIME, size, dates,
  permissions and owner.
- **Empty Trash** shortcut with a live item count in the bottom-right corner
  (can be hidden in settings). Right-click it to open or empty the trash.
- **Quick look** (`Space`): images, text files, and thumbnails for video/PDF.
- File badges: symlink, executable and read-only markers on the icon.
- **Video and PDF thumbnails** (needs `ffmpeg` / `pdftoppm`).
- Icon metadata is cached, so refreshing the desktop does not re-run MIME lookups.
- `Delete` moves the selection to trash (optional confirmation), `F2` renames
  (the extension is preserved), `F5` refreshes.
- **Applications tab**: list of installed apps (with search), multi-select and
  "Create shortcuts" writes executable `.desktop` files to the desktop.
- **Desktop widgets** (Widgets tab), any number of instances, each draggable and
  right-clickable (duplicate / remove):
  - clock — digital, analog or minimal;
  - calendar — full month or compact;
  - date & time — stacked or inline;
  - sticky notes in yellow/pink/blue/green, duplicated like fridge stickers with
    their text;
  - timer — ring or pill, with a shortcut to GNOME Clocks for alarms;
  - mini paint — paper or board canvas, saved as PNG and copied on duplicate.
  - custom widgets written in Lua (drawing, input, animation and persistent state).
  Widget state lives in `~/.local/state/quickshell/user/desktop-widgets.json`,
  drawings in `~/.local/state/quickshell/user/desktop-widgets/`.
- `.desktop` entries show their real `Name=` and `Icon=` and are launched with
  `gio launch` (so `Exec`, `Terminal`, placeholders work).
- Regular files use the icon of their default application for that MIME type
  (e.g. `.txt` shows the text editor icon, `.zip` the archive manager icon).
- "Open" resolves the default app for the MIME type explicitly, so files without an
  association (e.g. empty files) do not fall back to the browser via `$BROWSER`.

## Keyboard shortcuts

| Action | Shortcut |
| Open selected icon | double click |
| Toggle icon in selection | `Ctrl+Click` / `Ctrl+RightClick` |
| Select all | `Ctrl+A` |
| Clear selection | `Esc` |
| Move selection | arrow keys / `Home` / `End` |
| Open selected | `Enter` |
| Quick look | `Space` |
| Select range | `Shift+Click` |
| Undo last delete/rename/move | `Ctrl+Z` |
| Delete selection to trash | `Delete` |
| Rename | `F2` |
| Refresh (with pop-in wave) | `F5` |
| Copy / cut / paste | `Ctrl+C` / `Ctrl+X` / `Ctrl+V` |
| Zoom grid | `Ctrl+wheel` |

## Desktop settings

Right-click the desktop → **Desktop settings**. Everything applies live, split into tabs:

- **General**: show icons, show on all screens (multi-monitor), show icon labels,
  remember positions, auto arrange, snap to grid.
- **Grid**: direction (columns/rows), cell width, cell height, margin.
- **Colors**: icon selection color and opacity, text color, selection rectangle
  (rubber band) color and opacity. Each colour has a live swatch, a HEX field, a full
  HSV picker (saturation/value square + hue strip) with RGB/HSV readout, and a palette
  of 32 presets. The rectangle color follows the icon selection color until it is
  customized separately.
- **Arrange**: by name/type/size/date, reset positions.
- **Language**: switches the add-on's language only (English, Russian, Ukrainian,
  Belarusian, Polish, German, French, Spanish, Japanese, Chinese, Korean). The rest of
  the shell keeps its own language.
- **Applications**: search installed applications, select one or several and create
  `.desktop` shortcuts for them on the desktop.
- **Widgets**: add clock, calendar, date & time, notes, timer and mini-paint widgets
  (with style variants), remove all of them, or use the desktop right-click menu on a
  widget to duplicate or remove it.
- **Done** closes the modal (it also closes from the `×` button or `Esc`; clicking the
  desktop does not dismiss it).

## Custom widgets (Lua)

Any `.lua` file in `<desktop folder>/.widgets/` (default `~/Desktop/.widgets/`) is a widget.
The folder follows the desktop folder from the settings and is hidden from the icon grid. Add it
from **Settings → Widgets → Custom widgets** (there is a **Create example** button and
**Open folder** shortcut). Right-click a custom widget → **Reload script** after editing.
Each instance runs in its own `lua` process; a script error is shown on the widget and
its full message goes to stderr.

A widget is a table returned by the script (or assigned to the global `widget`):

```lua
local W = {
    width = 300,      -- preferred size (the host resizes the card to match)
    height = 180,
    tick = 50,        -- animation interval in ms, 0 = no timer
}

function W.render(w, h)
    return {
        { type = "rect",   x = 0, y = 0, w = w, h = h, radius = 16, color = "#12141a" },
        { type = "circle", x = w / 2, y = 70, r = 30, color = "#82aaff" },
        { type = "text",   x = w / 2, y = h - 24, text = "hello", size = 14,
          color = "#ffffff", align = "center" },
    }
end

function W.on_click(x, y, button)
    W.state.clicks = (W.state.clicks or 0) + 1
end

return W
```

Drawing operations (widget-local pixels):

| op | fields |
|---|---|
| `rect` | `x, y, w, h, radius, color, border, borderColor` |
| `circle` | `x, y, r, color, border, borderColor` |
| `line` | `x1, y1, x2, y2, width, color` |
| `text` | `x, y, text, size, color, align, valign, font` |
| `image` | `src, x, y, w, h` |
| `arc` | `x, y, r, from, to, width, color` (radians) |

Callbacks: `init(w, h, style)`, `render(w, h)`, `on_tick(ms)`, `on_press(x, y, button)`,
`on_move(x, y, buttons)`, `on_release(x, y, button)`, `on_click(x, y, button)`,
`on_double_click(x, y)`, `on_wheel(dy)`. `button` is `"left"`, `"right"` or `"middle"`.
`W.state` is a persistent table, saved next to the widget state and restored on restart.

The top 34 px of a custom widget are reserved for dragging the card; draw your content
below that (or leave the area empty).

## Quick look

Press `Space` on a file to preview it (images, text, video/PDF thumbnails).

## Screenshots

| Desktop | Rubber-band selection |
|---|---|
| ![Desktop](assets/screenshot.jpg) | ![Selection](assets/selection.jpg) |

| Icon context menu | Desktop context menu |
|---|---|
| ![Icon menu](assets/context-icon.png) | ![Desktop menu](assets/context-desktop.png) |

| General | Grid |
|---|---|
| ![General](assets/settings.jpg) | ![Grid](assets/grid.jpg) |

| Colors | Arrange |
|---|---|
| ![Colors](assets/colors.jpg) | ![Arrange](assets/arrange.jpg) |

| Language | Applications |
|---|---|
| ![Language](assets/language.jpg) | ![Applications](assets/apps.jpg) |

## Requirements

- illogical-impulse (quickshell `ii`) on Hyprland, tested with Quickshell 0.3.2.
- `gio` (glib2), `file`, `xdg-utils` (`xdg-mime`).
- `zip` for the Compress action, `tar` for tar.gz.
- Rust toolchain (`cargo`) — the helper is compiled during installation.
- `ffmpeg` (video thumbnails) and `pdftoppm` from poppler (PDF thumbnails) — optional.
- `Qt.labs.folderlistmodel` (ships with Qt 6 declarative).
- `lua` in `PATH` for custom Lua widgets (Lua 5.1+; tested with 5.4/5.5).

## Install

```bash
git clone https://github.com/0xcds4r/illogical-desktop.git
cd illogical-desktop
./install.sh
pkill -x qs; setsid -f qs -c ii
```

`install.sh` copies the module and builds the helper, writes the add-on's own settings/state
files (migrating values from older installs), and injects a single `Loader` into
`Background.qml` using structural anchors. It is idempotent: running it again does
nothing. Pass a path as the first argument for a non-default config location.

Manual install:

1. Copy `files/modules/ii/background/desktop/` into
   `~/.config/quickshell/ii/modules/ii/background/desktop/`.
2. Build the helper: `cargo build --release --manifest-path rust/Cargo.toml` and copy
   `rust/target/release/desktop-helper` into `~/.config/quickshell/ii/scripts/`.
3. Add `import qs.modules.ii.background.desktop` to `Background.qml` and insert the
   `Loader` block from `install.sh` before `WidgetCanvas`.

## Configuration

The add-on keeps its settings in its own file,
`~/.config/illogical-impulse/desktop-icons.json` (not in the shell's `config.json`):

```json
{
    "enable": true,
    "showOnAllScreens": false,
    "showLabels": true,
    "persistPositions": true,
    "autoArrange": false,
    "snapToGrid": false,
    "gridMode": "columns",
    "cellWidth": 96,
    "cellHeight": 104,
    "margin": 24,
    "selectionColor": "#4A90D9",
    "selectionOpacity": 0.35,
    "textColor": "#FFFFFF",
    "bandColor": "#4A90D9",
    "bandOpacity": 0.18,
    "language": "en",
    "folder": "",
    "confirmDelete": false,
    "showTrash": true
}
```

- `showOnAllScreens`: load the desktop on every monitor. With a single monitor it has
  no visible effect (icons always show there); with several, each screen gets its own
  grid and its own saved positions.
- `gridMode`: `"columns"` (top to bottom, then next column) or `"rows"`.
- `snapToGrid`: align positions to cells; dropping onto an occupied cell swaps icons.
- `autoArrange`: always use the automatic grid (drops do not persist).
- `showLabels`: show the filename under each icon; when off, icons are centered in the cell.
- `selectionColor` / `selectionOpacity`: icon selection highlight.
- `textColor`: icon labels.
- `bandColor` / `bandOpacity`: rubber-band selection rectangle.
- `language`: language of the add-on UI only (`en`, `ru`, `uk`, `be`, `pl`, `de`, `fr`,
  `es`, `ja`, `zh`, `ko`). The shell language is not changed.
- `folder`: custom folder to show instead of `~/Desktop` (empty means `~/Desktop`).
- `confirmDelete`: ask before moving the selection to trash.
- `showTrash`: show the trash shortcut in the bottom-right corner.
- Icon positions are stored in `~/.local/state/quickshell/user/desktop-positions.json`.
- Older installs migrated automatically from `config.json` / `states.json` on first run.

## Repository layout

```
files/modules/ii/background/desktop/
  DesktopIcons.qml        grid, selection, drag & drop, menus, actions
  DesktopIcon.qml         icon delegate (labels, .desktop icons, file icons)
  DesktopContextMenu.qml  context menu renderer
  DesktopFileOps.qml      file operations (copy, trash, link, compress, ...)
  DesktopSettings.qml     settings modal
  DesktopProperties.qml   properties modal
  DesktopIconCache.qml    metadata cache for smooth refreshes
  DesktopConfig.qml       own settings file
  DesktopPositions.qml    own icon-position state file
rust/                     Rust helper (trash, icons, open, props, compress)
install.sh                installer (builds helper, injects loader)
uninstall.sh              removes the module, helper and injected loader
```

## Compatibility with shell updates

The add-on does not modify `Config.qml` or `Persistent.qml`; settings and positions
live in its own files. The only hook is one `Loader` inserted into `Background.qml`
before `WidgetCanvas` (plus a keyboard-focus line and an import), so a shell update
usually cannot break the install: re-running `install.sh` re-copies the module and,
if upstream changed the file, injects the loader again.

It is not an absolute guarantee: if upstream renames/restructures `Background.qml` so
that the `WidgetCanvas` anchor no longer exists, the installer stops with a clear
error instead of corrupting the file. In that case the `Loader` block needs a new
anchor.

## Limitations

- Clipboard is internal to the shell; dragging files in from a file manager or out to
  another app is not implemented (Wayland layer-shell data devices).
- Rubber-band selection works on the desktop surface only.
- With `showOnAllScreens` off, secondary monitors have no desktop context menu or
  settings modal (the module is not loaded there).
- The rename editor and both modals use fullscreen overlay layers (needed for keyboard
  focus).
- Compress follows symlinks: the archive stores the link target's contents.

## Uninstall

```bash
./uninstall.sh
pkill -x qs; setsid -f qs -c ii
```

This removes the module, scripts and the injected loader; settings and positions are
kept (delete `~/.config/illogical-impulse/desktop-icons.json` and
`~/.local/state/quickshell/user/desktop-positions.json` to reset them).

## License

MIT, see [LICENSE](LICENSE).
