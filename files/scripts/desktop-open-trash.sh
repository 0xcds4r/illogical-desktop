#!/usr/bin/env bash
# Open the trash in a file manager (xdg-open often falls back to a browser for
# the trash:// scheme when no handler is registered).
set -uo pipefail

default_manager="$(xdg-mime query default inode/directory 2>/dev/null || true)"

case "$default_manager" in
	*dolphin*)
		command -v dolphin >/dev/null && exec dolphin "trash:/"
		;;
	*nautilus*)
		command -v nautilus >/dev/null && exec nautilus "trash://"
		;;
	*thunar*)
		command -v thunar >/dev/null && exec thunar "trash://"
		;;
esac

if command -v nautilus >/dev/null; then
	exec nautilus "trash://"
elif command -v dolphin >/dev/null; then
	exec dolphin "trash:/"
elif command -v thunar >/dev/null; then
	exec thunar "trash://"
fi

exec gio open "trash://"
