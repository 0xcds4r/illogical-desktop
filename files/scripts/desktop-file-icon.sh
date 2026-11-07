#!/usr/bin/env bash
# Resolve the icon to use for a file based on the system default application.
# Output, one line: kind<TAB>value<TAB>flags
#   thumb      -> caller should show an image preview (image files)
#   filethumb  -> value is a generated thumbnail path (video/pdf)
#   name       -> icon theme name
#   path       -> absolute icon path
# flags: comma-separated subset of link,exec,readonly
set -uo pipefail

path="${1:-}"
[[ -z "$path" ]] && exit 0

mime="$(file --mime-type -b -- "$path" 2>/dev/null)"
[[ -z "$mime" ]] && exit 0

flags=""
[[ -L "$path" ]] && flags+="link,"
if [[ -f "$path" && -x "$path" ]]; then flags+="exec,"; fi
if [[ ! -w "$path" ]]; then flags+="readonly,"; fi
flags="${flags%,}"

thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/media/desktop-thumbs"
mkdir -p "$thumb_dir" 2>/dev/null

make_thumb() {
	local kind="$1"
	local stamp hash out
	stamp="$(stat -c '%Y' -- "$path" 2>/dev/null)"
	hash="$(printf '%s\n%s\n%s' "$path" "$stamp" "$kind" | sha1sum | cut -d' ' -f1)"
	out="$thumb_dir/$hash.png"
	if [[ -s "$out" ]]; then
		printf 'filethumb\t%s\t%s\n' "$out" "$flags"
		return 0
	fi
	if [[ "$kind" == "video" ]]; then
		command -v ffmpeg >/dev/null || return 1
		ffmpeg -y -loglevel error -ss 1 -i "$path" -frames:v 1 -vf "scale=256:-2" -an "$out" 2>/dev/null
	elif [[ "$kind" == "pdf" ]]; then
		command -v pdftoppm >/dev/null || return 1
		pdftoppm -f 1 -l 1 -singlefile -png -scale-to 256 "$path" "${out%.png}" 2>/dev/null
	fi
	[[ -s "$out" ]] || return 1
	printf 'filethumb\t%s\t%s\n' "$out" "$flags"
}

if [[ "$mime" == image/* ]]; then
	printf 'thumb\t\t%s\n' "$flags"
	exit 0
fi

if [[ "$mime" == video/* ]]; then
	make_thumb video && exit 0
fi

if [[ "$mime" == application/pdf ]]; then
	make_thumb pdf && exit 0
fi

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
		printf 'path\t%s\t%s\n' "$icon" "$flags"
	else
		printf 'name\t%s\t%s\n' "$icon" "$flags"
	fi
	exit 0
fi

printf 'name\t%s\t%s\n' "${mime//\//-}" "$flags"
