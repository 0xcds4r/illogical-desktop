#!/usr/bin/env bash
# Print properties for a file as tab-separated "Label<TAB>Value" lines.
set -uo pipefail

path="${1:-}"
if [[ -z "$path" || (! -e "$path" && ! -L "$path") ]]; then
	printf 'Name\t—\n'
	printf 'Path\t%s\n' "$path"
	exit 0
fi

name="$(basename -- "$path")"
printf 'Name\t%s\n' "$name"
printf 'Path\t%s\n' "$path"

if [[ -L "$path" ]]; then
	printf 'Type\tSymbolic link\n'
	printf 'Target\t%s\n' "$(readlink -- "$path")"
elif [[ -d "$path" ]]; then
	printf 'Type\tFolder\n'
else
	printf 'Type\tFile\n'
fi

mime="$(file --mime-type -b -- "$path" 2>/dev/null)"
[[ -n "$mime" ]] && printf 'MIME\t%s\n' "$mime"

if [[ -d "$path" ]]; then
	size="$(du -sh -- "$path" 2>/dev/null | cut -f1)"
	[[ -n "$size" ]] && printf 'Size\t%s\n' "$size"
else
	bytes="$(stat -c %s -- "$path" 2>/dev/null)"
	if [[ -n "$bytes" ]]; then
		human="$(numfmt --to=iec --suffix=B "$bytes" 2>/dev/null)"
		printf 'Size\t%s%s\n' "${human:-$bytes}" "${human:+ ($bytes bytes)}"
	fi
fi

modified="$(stat -c %y -- "$path" 2>/dev/null | cut -d. -f1)"
[[ -n "$modified" ]] && printf 'Modified\t%s\n' "$modified"

permissions="$(stat -c '%A (%a)' -- "$path" 2>/dev/null)"
[[ -n "$permissions" ]] && printf 'Permissions\t%s\n' "$permissions"

owner="$(stat -c '%U:%G' -- "$path" 2>/dev/null)"
[[ -n "$owner" ]] && printf 'Owner\t%s\n' "$owner"
