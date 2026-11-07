#!/usr/bin/env bash
# Remove the illogical-desktop add-on from an illogical-impulse (quickshell ii) config.
#
# Usage: ./uninstall.sh [path-to-ii-config]
# Default target: ~/.config/quickshell/ii
set -euo pipefail

TARGET="${1:-$HOME/.config/quickshell/ii}"

if [[ ! -d "$TARGET/modules/ii/background" ]]; then
	echo "error: $TARGET does not look like an illogical-impulse config" >&2
	exit 1
fi

rm -rf "$TARGET/modules/ii/background/desktop"
rm -f "$TARGET/scripts/"desktop-*

python3 - "$TARGET" <<'PY'
import os
import sys

path = os.path.join(sys.argv[1], "modules/ii/background/Background.qml")
with open(path, encoding="utf-8") as fh:
    lines = fh.read().splitlines(keepends=True)

out = []
skip = False
removed = False
for line in lines:
    stripped = line.strip()
    if stripped == "// >>> illogical-desktop >>>":
        skip = True
        removed = True
        continue
    if stripped == "// <<< illogical-desktop <<<":
        skip = False
        continue
    if skip:
        continue
    if stripped == "import qs.modules.ii.background.desktop":
        continue
    if "WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand" in line:
        continue
    out.append(line)

if removed:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(out))
    print("  removed loader from Background.qml")
else:
    print("  no loader marker found")
PY

echo
echo "Removed. Restart quickshell:"
echo "  pkill -x qs; setsid -f qs -c ii"
echo
echo "Settings and icon positions were kept:"
echo "  ~/.config/illogical-impulse/desktop-icons.json"
echo "  ~/.local/state/quickshell/user/desktop-positions.json"
