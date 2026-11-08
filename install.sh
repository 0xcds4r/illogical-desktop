#!/usr/bin/env bash
# Install the illogical-desktop add-on into an illogical-impulse (quickshell ii) config.
#
# The add-on keeps its data in its own files and injects a single Loader into
# Background.qml using structural anchors, so it does not depend on the exact
# contents of the shell's Config.qml / Persistent.qml.
#
# Usage: ./install.sh [path-to-ii-config]
# Default target: ~/.config/quickshell/ii
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$HOME/.config/quickshell/ii}"

if [[ ! -d "$TARGET/modules/ii/background" || ! -d "$TARGET/scripts" || ! -f "$TARGET/modules/ii/background/Background.qml" ]]; then
	echo "error: $TARGET does not look like an illogical-impulse config" >&2
	exit 1
fi

echo "Installing into $TARGET"

# 1. Module files.
mkdir -p "$TARGET/modules/ii/background/desktop/lua"
cp "$HERE/files/modules/ii/background/desktop/"*.qml "$TARGET/modules/ii/background/desktop/"
cp "$HERE/files/modules/ii/background/desktop/lua/"*.lua "$TARGET/modules/ii/background/desktop/lua/"

# 2. Build and install the Rust helper.
if ! command -v cargo >/dev/null 2>&1; then
	echo "error: Rust/cargo is required to build desktop-helper" >&2
	exit 1
fi
cargo build --release --manifest-path "$HERE/rust/Cargo.toml"
install -m755 "$HERE/rust/target/release/desktop-helper" "$TARGET/scripts/desktop-helper"
# Remove helpers from older versions.
rm -f "$TARGET/scripts/"desktop-*.sh "$TARGET/scripts/"desktop-*.py

# 3. Migrate settings/positions from the old location (only on first install).
python3 - "$TARGET" <<'PY'
import json
import os
import sys

home = os.path.expanduser("~")
config_path = os.path.join(home, ".config/illogical-impulse/desktop-icons.json")
positions_path = os.path.join(home, ".local/state/quickshell/user/desktop-positions.json")

defaults = {
    "enable": True,
    "showOnAllScreens": False,
    "showLabels": True,
    "persistPositions": True,
    "autoArrange": False,
    "snapToGrid": False,
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
    "confirmDelete": False,
    "showTrash": True,
}

if not os.path.exists(config_path):
    values = dict(defaults)
    old_config = os.path.join(home, ".config/illogical-impulse/config.json")
    try:
        with open(old_config, encoding="utf-8") as fh:
            old = json.load(fh)
        old_values = old.get("background", {}).get("desktopIcons", {})
        for key in defaults:
            if key in old_values:
                values[key] = old_values[key]
    except Exception:
        pass
    os.makedirs(os.path.dirname(config_path), exist_ok=True)
    with open(config_path, "w", encoding="utf-8") as fh:
        json.dump(values, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("  wrote", config_path)
else:
    print("  keeping existing", config_path)

if not os.path.exists(positions_path):
    positions = []
    old_states = os.path.join(home, ".local/state/quickshell/states.json")
    try:
        with open(old_states, encoding="utf-8") as fh:
            old = json.load(fh)
        positions = old.get("desktop", {}).get("iconPositions", [])
    except Exception:
        pass
    os.makedirs(os.path.dirname(positions_path), exist_ok=True)
    with open(positions_path, "w", encoding="utf-8") as fh:
        json.dump({"iconPositions": positions}, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print("  wrote", positions_path)
else:
    print("  keeping existing", positions_path)
PY

# 4. Inject the loader into Background.qml using structural anchors.
python3 - "$TARGET" <<'PY'
import os
import re
import sys

target = sys.argv[1]
path = os.path.join(target, "modules/ii/background/Background.qml")
with open(path, encoding="utf-8") as fh:
    source = fh.read()

marker = "// >>> illogical-desktop >>>"
changed = False

if marker in source or "desktopIconsLoader" in source:
    print("  Background.qml already patched")
else:
    lines = source.splitlines()

    # Import for the module singletons.
    if "import qs.modules.ii.background.desktop" not in source:
        last_import = max(i for i, line in enumerate(lines) if line.startswith("import "))
        lines.insert(last_import + 1, "import qs.modules.ii.background.desktop")
        changed = True

    # Keyboard focus, needed for Delete / Ctrl+C / Ctrl+V / F5 on the desktop.
    if "WlrLayershell.keyboardFocus" not in source:
        for i, line in enumerate(lines):
            if "WlrLayershell.layer:" in line:
                indent = line[: len(line) - len(line.lstrip())]
                lines.insert(i + 1, f"{indent}WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand")
                changed = True
                break

    # Insert the loader before the widget canvas (present in all known versions).
    anchor_index = None
    anchor_text = None
    for candidate in ("WidgetCanvas {", "id: widgetCanvas"):
        for i, line in enumerate(lines):
            if candidate in line:
                anchor_index = i
                anchor_text = line
                break
        if anchor_index is not None:
            break

    if anchor_index is None:
        print("error: could not find the desktop insertion anchor in Background.qml", file=sys.stderr)
        sys.exit(2)

    indent = anchor_text[: len(anchor_text) - len(anchor_text.lstrip())]
    inner = indent + "    "
    block = [
        f"{indent}// >>> illogical-desktop >>>",
        f"{indent}Loader {{",
        f"{inner}id: desktopIconsLoader",
        f"{inner}anchors.fill: parent",
        f"{inner}z: 5",
        f"{inner}active: DesktopConfig.showOnAllScreens ||",
        f"{inner}    (Quickshell.screens.length > 0 && modelData.name === Quickshell.screens[0].name)",
        f"{inner}sourceComponent: DesktopIcons {{",
        f"{inner}    screenName: modelData.name",
        f"{inner}    screenRef: modelData",
        f"{inner}}}",
        f"{indent}}}",
        f"{indent}// <<< illogical-desktop <<<",
        "",
    ]
    lines[anchor_index:anchor_index] = block
    changed = True

    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("  injected loader into Background.qml")

if not changed:
    print("  nothing to inject")
PY

# 5. Seed the example Lua widget for the current user (never overwrite it).
custom_dir="$HOME/.config/illogical-impulse/desktop-widgets"
mkdir -p "$custom_dir"
if [[ ! -f "$custom_dir/example.lua" ]]; then
	cp "$HERE/files/modules/ii/background/desktop/lua/example.lua" "$custom_dir/example.lua"
	echo "  wrote $custom_dir/example.lua"
fi

echo
echo "Done. Restart quickshell to load the desktop:"
echo "  pkill -x qs; setsid -f qs -c ii"
