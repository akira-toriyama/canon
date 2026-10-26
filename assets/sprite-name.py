#!/usr/bin/env python3
"""The name the Prospector Dongle shows above its HP bar for a sprite GIF of a
local build (scripts/build-zmk.sh --sprite), printed on stdout:

  assets/sprite-name.py <gif>

The user's rule (projects t-rq9h, 2026-10-26): the katakana name when the
HP bar can show it, else the name as before. The katakana name comes from
the sprite sender's name dictionary, looked up as the sender does (zmk-beacon
tools/sprite-sender, SpriteSenderCore/SpriteName.swift): the GIF's directory
is the `front` of a `sender.json` in it or above it (the collection's; its
keys relative to it), the GIF's position among the `order` file's names,
counted from 1 (an empty line or a repeated name holds none), is its place,
and the `names` file's entry of that place gives `ja`, composed
(NFC), taken when it is 15 bytes of UTF-8 at most and every character is in
the katakana font (KATAKANA_RANGES, a copy of zmk-beacon's
sprite_pack.KATAKANA_RANGES: change the two together). Without a config, an
order, a dictionary or an entry, or with one the HP bar cannot show, the
name as before (projects t-er81): the GIF's file name with its extension
dropped (`.gif` alone leaves nothing), whitespace trimmed at both ends, the
first letter upper-cased ("my sprite.gif" -> "My sprite"), cut to the 15
bytes a sprite pack's name holds (zmk-beacon's build stops on a longer one
since c92ffcf). That name is printable ASCII on one line without a double
quote, a backslash or "??": the name row's ASCII font has no other glyphs,
Kconfig would need escaping, and "??x" is a C trigraph in autoconf.h, so
anything else is an error (exit 2) and a build never shows a wrong name. A
katakana name has none of those characters. One line on stderr says where
the name came from, as the sender's log does, naming nothing.

build-zmk.sh passes the name to zmk-beacon as CONFIG_BEACON_SPRITE_NAME,
whose sprite_pack.py checks it again. Committed, like assets/README.md: the
two exceptions to the ignore rule on assets/, while the personal files live
off the repository. The name names the subject, so never paste the output
into a commit, a PR or a doc; the messages name neither the file nor the
name for the same reason. Standard library only, macOS /usr/bin/python3 (3.9).
"""
import json
import os
import sys
import unicodedata

NAME_BYTES = 15
CONFIG_NAME = "sender.json"
KATAKANA_RANGES = ((0x2640, 0x2640), (0x2642, 0x2642), (0x30A1, 0x30FC), (0xFF10, 0xFF1A),
                   (0xFF21, 0xFF3A))


class NameError_(ValueError):
    """The file name gives no name (exit 2)."""


def note(why):
    print("sprite-name: %s" % why, file=sys.stderr)


def from_file_name(file_name):
    """The name as before, from the GIF's file name; NameError_ when it
    gives none."""
    stem = file_name.rsplit(".", 1)[0] if "." in file_name else file_name
    name = stem.strip()
    if not name:
        raise NameError_("the GIF's file name leaves no name")
    if "\n" in name or "\r" in name:
        raise NameError_("the GIF's file name must be one line")
    if not all(" " <= c <= "~" for c in name) or '"' in name or "\\" in name or "??" in name:
        raise NameError_('the GIF\'s file name must be printable ASCII without a double quote, '
                         'a backslash or "??"')
    name = name[0].upper() + name[1:]
    return name[:NAME_BYTES]


def katakana(text):
    """The dictionary's name as the pack takes it, or None with the reason
    the HP bar cannot show it."""
    name = unicodedata.normalize("NFC", text)
    if not name:
        return None, "the dictionary has no name for its place"
    if len(name.encode("utf-8")) > NAME_BYTES:
        return None, "the dictionary's name is longer than %d bytes" % NAME_BYTES
    if not all(any(lo <= ord(c) <= hi for lo, hi in KATAKANA_RANGES) for c in name):
        return None, "the dictionary's name has a character the katakana font lacks"
    return name, None


def find_config(directory):
    """(config dir, config) of the sender.json in `directory` or above it
    whose `front` is `directory`; None without one."""
    here = os.path.realpath(directory)
    candidate = here
    while True:
        path = os.path.join(candidate, CONFIG_NAME)
        if os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    config = json.load(f)
            except (OSError, ValueError):
                config = None
            if isinstance(config, dict) and isinstance(config.get("front"), str) and config["front"]:
                front = os.path.realpath(os.path.join(candidate, config["front"]))
                if front == here:
                    return candidate, config
        parent = os.path.dirname(candidate)
        if parent == candidate:
            return None
        candidate = parent


def read_order(path):
    """The order file's names, composed (NFC): one a line, exactly, empty
    lines skipped, a name's first line its place (the sender's
    Rotation.order, whose Set<String> takes a decomposed spelling for the
    composed one)."""
    with open(path, "rb") as f:
        data = f.read()
    names = []
    seen = set()
    for line in data.split(b"\n"):
        if line.endswith(b"\r"):
            line = line[:-1]
        if not line:
            continue
        name = unicodedata.normalize("NFC", line.decode("utf-8", "replace"))
        if name not in seen:
            seen.add(name)
            names.append(name)
    return names


def read_names(path):
    """{place: ja} of the name dictionary (the sender's NameDictionary: an
    array of objects with an integer `no`, `ja` optional, other keys
    ignored); None when the file is not that."""
    try:
        with open(path, encoding="utf-8") as f:
            entries = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(entries, list):
        return None
    japanese = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("no"), int) or isinstance(entry.get("no"), bool):
            return None
        if entry["no"] in japanese:
            return None
        ja = entry.get("ja")
        japanese[entry["no"]] = ja if isinstance(ja, str) else None
    return japanese


def from_dictionary(gif):
    """The katakana name of the GIF, or None with the reason."""
    found = find_config(os.path.dirname(gif))
    if found is None:
        return None, "no sender.json whose front is the GIF's directory"
    base, config = found
    order_path = config.get("order")
    names_path = config.get("names")
    if not isinstance(order_path, str) or not order_path or not isinstance(names_path, str) or not names_path:
        return None, "the config names no order file or no dictionary"
    try:
        order = read_order(os.path.join(base, order_path))
    except OSError:
        return None, "cannot read the order file"
    file_name = unicodedata.normalize("NFC", os.path.basename(gif))
    if file_name not in order:
        return None, "the GIF is not in the order"
    place = order.index(file_name) + 1
    japanese = read_names(os.path.join(base, names_path))
    if japanese is None:
        return None, "the dictionary is not an array of numbered objects"
    if place not in japanese or japanese[place] is None:
        return None, "the dictionary has no name for its place"
    return katakana(japanese[place])


def main(argv):
    if len(argv) != 1 or not argv[0]:
        print("usage: sprite-name.py <gif>", file=sys.stderr)
        return 2
    gif = os.path.abspath(argv[0])
    name, why = from_dictionary(gif)
    if name is not None:
        note("katakana from the name dictionary, %d characters, %d bytes" % (len(name), len(name.encode("utf-8"))))
    else:
        try:
            name = from_file_name(os.path.basename(gif))
        except NameError_ as e:
            note(str(e))
            return 2
        note("from the file name (%s), %d characters" % (why, len(name)))
    sys.stdout.write(name + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
