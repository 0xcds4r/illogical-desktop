#!/usr/bin/env bash
# List applications that can open a file/directory.
# Output: id<TAB>name<TAB>icon<TAB>desktop-file-path (one per line)
set -uo pipefail

path="${1:-}"
[[ -z "$path" ]] && exit 0

mime="$(file --mime-type -b -- "$path" 2>/dev/null)"
[[ -z "$mime" ]] && exit 0
# Empty files report inode/x-empty, which has no application associations.
[[ "$mime" == "inode/x-empty" ]] && mime="text/plain"

mapfile -t ids < <(gio mime "$mime" 2>/dev/null | sed -n 's/^\t//p')

declare -A seen=()
for id in "${ids[@]}"; do
	[[ -z "$id" ]] && continue
	[[ -n "${seen[$id]:-}" ]] && continue
	seen[$id]=1

	desktop_file=""
	for dir in \
		"$HOME/.local/share/applications" \
		"/usr/share/applications" \
		"/var/lib/flatpak/exports/share/applications" \
		"$HOME/.local/share/flatpak/exports/share/applications"; do
		if [[ -f "$dir/$id" ]]; then
			desktop_file="$dir/$id"
			break
		fi
	done
	[[ -z "$desktop_file" ]] && continue

	name="$(grep -m1 '^Name=' "$desktop_file" 2>/dev/null | cut -d= -f2-)"
	icon="$(grep -m1 '^Icon=' "$desktop_file" 2>/dev/null | cut -d= -f2-)"
	printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$icon" "$desktop_file"
done
