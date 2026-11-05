#!/usr/bin/env bash
# Install the illogical-desktop add-on into an illogical-impulse (quickshell ii) config.
#
# Usage: ./install.sh [path-to-ii-config]
# Default target: ~/.config/quickshell/ii
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$HOME/.config/quickshell/ii}"

if [[ ! -d "$TARGET/modules/ii/background" || ! -d "$TARGET/scripts" ]]; then
	echo "error: $TARGET does not look like an illogical-impulse config" >&2
	exit 1
fi

echo "Installing into $TARGET"

# 1. New module files.
mkdir -p "$TARGET/modules/ii/background/desktop"
cp "$HERE/files/modules/ii/background/desktop/"*.qml "$TARGET/modules/ii/background/desktop/"

# 2. Helper scripts.
cp "$HERE/files/scripts/"desktop-*.sh "$TARGET/scripts/"
chmod +x "$TARGET/scripts/"desktop-*.sh

# 3. Patch the three existing files. Already-applied patches are skipped.
for p in "$HERE"/patches/*.patch; do
	if patch -p1 -d "$TARGET" --dry-run --force --silent <"$p" >/dev/null 2>&1; then
		patch -p1 -d "$TARGET" --force --silent <"$p"
		echo "  applied $(basename "$p")"
	else
		echo "  skipped $(basename "$p") (already applied or conflict)"
	fi
done

echo
echo "Done. Restart quickshell to load the desktop:"
echo "  pkill -x qs; setsid -f qs -c ii"
