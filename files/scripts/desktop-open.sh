#!/usr/bin/env bash
# Open a file with the system default application for its content type.
# Resolves the association explicitly so that files without a MIME association
# (e.g. empty files) do not fall back to the browser via $BROWSER.
set -uo pipefail

path="${1:-}"
[[ -z "$path" ]] && exit 0

mime="$(file --mime-type -b -- "$path" 2>/dev/null)"
[[ -z "$mime" ]] && mime="$(xdg-mime query filetype "$path" 2>/dev/null)"
[[ "$mime" == "inode/x-empty" ]] && mime="text/plain"

desktop_file=""
if [[ -n "$mime" ]]; then
	app_id="$(xdg-mime query default "$mime" 2>/dev/null)"
	[[ "$app_id" == *.desktop ]] || app_id=""
	if [[ -n "$app_id" ]]; then
		for dir in \
			"$HOME/.local/share/applications" \
			"/usr/share/applications" \
			"/var/lib/flatpak/exports/share/applications" \
			"$HOME/.local/share/flatpak/exports/share/applications"; do
			if [[ -f "$dir/$app_id" ]]; then
				desktop_file="$dir/$app_id"
				break
			fi
		done
	fi
fi

if [[ -n "${DRY_RUN:-}" ]]; then
	printf '%s\t%s\n' "$mime" "${desktop_file:-<fallback>}"
	exit 0
fi

if [[ -n "$desktop_file" ]]; then
	exec gio launch "$desktop_file" "$path"
fi

exec gio open "$path"
