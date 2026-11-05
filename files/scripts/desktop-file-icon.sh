#!/usr/bin/env bash
# Resolve the icon to use for a file based on the system default application.
# Output, one line:
#   thumb            -> caller should show an image preview (image files)
#   name<TAB>icon    -> icon theme name
#   path<TAB>/abs    -> absolute icon path
#   (nothing)        -> caller falls back to the generic mime icon
set -uo pipefail

path="${1:-}"
[[ -z "$path" ]] && exit 0

mime="$(file --mime-type -b -- "$path" 2>/dev/null)"
[[ -z "$mime" ]] && exit 0

# Images keep their real thumbnail.
if [[ "$mime" == image/* ]]; then
	printf 'thumb\t\n'
	exit 0
fi

# Empty files behave like plain text for application lookup.
lookup_mime="$mime"
[[ "$lookup_mime" == "inode/x-empty" ]] && lookup_mime="text/plain"

app_id="$(xdg-mime query default "$lookup_mime" 2>/dev/null)"
[[ "$app_id" == *.desktop ]] || app_id=""

icon=""
if [[ -n "$app_id" ]]; then
	for dir in \
		"$HOME/.local/share/applications" \
		"/usr/share/applications" \
		"/var/lib/flatpak/exports/share/applications" \
		"$HOME/.local/share/flatpak/exports/share/applications"; do
		desktop_file="$dir/$app_id"
		[[ -f "$desktop_file" ]] || continue
		icon="$(grep -m1 '^Icon=' "$desktop_file" 2>/dev/null | cut -d= -f2-)"
		break
	done
fi

if [[ -n "$icon" ]]; then
	if [[ "$icon" == /* ]]; then
		printf 'path\t%s\n' "$icon"
	else
		printf 'name\t%s\n' "$icon"
	fi
	exit 0
fi

# Fallback: generic mime icon (e.g. text-x-generic).
printf 'name\t%s\n' "${mime//\//-}"
