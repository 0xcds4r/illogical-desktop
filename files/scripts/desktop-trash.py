#!/usr/bin/env python3
"""Move files to the freedesktop trash, restore them, count and empty it."""

import os
import shutil
import sys
import time
import urllib.parse

TRASH = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "Trash")
FILES = os.path.join(TRASH, "files")
INFO = os.path.join(TRASH, "info")


def ensure():
    os.makedirs(FILES, exist_ok=True)
    os.makedirs(INFO, exist_ok=True)


def unique_dest(name):
    dest = os.path.join(FILES, name)
    if not os.path.lexists(dest):
        return dest
    counter = 2
    while True:
        dest = os.path.join(FILES, f"{name}.{counter}")
        if not os.path.lexists(dest):
            return dest
        counter += 1


def move(path):
    path = os.path.abspath(path)
    name = os.path.basename(path)
    dest = unique_dest(name)
    shutil.move(path, dest)
    info = os.path.join(INFO, os.path.basename(dest) + ".trashinfo")
    with open(info, "w", encoding="utf-8") as fh:
        fh.write("[Trash Info]\n")
        fh.write(f"Path={urllib.parse.quote(path)}\n")
        fh.write(f"DeletionDate={time.strftime('%Y-%m-%dT%H:%M:%S')}\n")


def info_paths():
    for name in os.listdir(INFO):
        if not name.endswith(".trashinfo"):
            continue
        full = os.path.join(INFO, name)
        original = None
        try:
            with open(full, encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("Path="):
                        original = urllib.parse.unquote(line[5:].strip())
                        break
        except OSError:
            continue
        if original:
            yield full, os.path.join(FILES, name[:-len(".trashinfo")]), original


def restore_by_original(original_paths):
    targets = {os.path.abspath(p) for p in original_paths}
    entries = sorted(info_paths(), key=lambda e: os.path.getmtime(e[0]), reverse=True)
    for info, trashed, original in entries:
        if original not in targets:
            continue
        if not os.path.lexists(trashed):
            continue
        os.makedirs(os.path.dirname(original), exist_ok=True)
        dest = original
        if os.path.exists(dest):
            base, ext = os.path.splitext(original)
            counter = 2
            while os.path.exists(dest):
                dest = f"{base}.{counter}{ext}"
                counter += 1
        shutil.move(trashed, dest)
        try:
            os.remove(info)
        except OSError:
            pass
        print(dest)


def count():
    ensure()
    print(len(os.listdir(FILES)))


def empty():
    ensure()
    for name in os.listdir(FILES):
        path = os.path.join(FILES, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path, ignore_errors=True)
        else:
            try:
                os.remove(path)
            except OSError:
                pass
    for name in os.listdir(INFO):
        try:
            os.remove(os.path.join(INFO, name))
        except OSError:
            pass


def main():
    if len(sys.argv) < 2:
        return 2
    command = sys.argv[1]
    ensure()
    if command == "move":
        for path in sys.argv[2:]:
            if os.path.exists(path) or os.path.islink(path):
                move(path)
    elif command == "restore":
        restore_by_original(sys.argv[2:])
    elif command == "count":
        count()
    elif command == "empty":
        empty()
    else:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
