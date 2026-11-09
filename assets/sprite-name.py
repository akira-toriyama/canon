#!/usr/bin/env python3
"""The name the Prospector Dongle shows above its HP bar for a sprite GIF of a
local build (scripts/build-zmk.sh --sprite), printed on stdout:

  assets/sprite-name.py [--sender-config <sender.json>] <gif>

The user's rule (projects t-rq9h, 2026-10-26): the katakana name when the HP
bar can show it, else as before. A GIF named `<number>.gif` takes its names from
the name dictionary, the CSV `names` of the sprite sender's config
(--sender-config, else $SPRITE_SENDER_CONFIG, which dotfiles sets), the rows of
that number: the Japanese row's name, composed (NFC), else the English row's,
whole, each when it is 15 bytes of UTF-8 at most and all in the katakana font or
all printable ASCII; the English name is first folded where the collection's
names need it and nowhere else (a gender sign at its end to a space and F or M,
a typographic apostrophe to the ASCII one: fold_english). That rule, the fold,
the CSV's columns and its language ids copy zmk-vfx-beacon's
tools/name_dictionary.py (its fold_english) and sprite_pack.KATAKANA_RANGES:
change them together. A copy, because this runs before the pinned clone is checked out,
and moving the pin moves every target's firmware stamp. The one difference is
Kconfig's, below.

Without a config, with a GIF of another name, a name dictionary with no name of
the number that fits, a config without a usable `names`, or a CSV the sender's
tool refuses (where those last two are a config error in the sender's daily run,
a build falls back and says so), the name as before (projects t-er81): the GIF's
file name with its extension dropped (`.gif` alone leaves nothing), spaces and
tabs trimmed at both ends, the first letter upper-cased ("my sprite.gif" -> "My
sprite"), cut to the 15 bytes a sprite pack's name holds (zmk-vfx-beacon's build
stops on a longer one since c92ffcf) and trimmed again. So `<number>.gif` then
shows the number. Only `names` is read: a config the sender refuses for another
key (`order`, `front`, `state`, `back`, `range`) still gives the name dictionary's
name, with no word of the refusal. An ASCII name is printable ASCII on one line
without a double quote, a backslash or "??": the name row's ASCII font has no
other glyphs, Kconfig would need escaping, and "??x" is a C trigraph in
autoconf.h, so a file name with anything else is an error (exit 2) and a build
never shows a wrong name. A katakana name has none of those characters. One line
on stderr says whether the name is katakana or ASCII, as the sender's log does,
and why a build fell back to the file name; never the name or its length (matched
against the public list of names, a rare length narrows the subject down to a
few). For a GIF of the collection the alphabet still says whether the katakana
name fit, a fact about the name, so the line stays out of commits, PRs and docs
like the name. stdout is UTF-8 whatever the locale.

build-zmk.sh passes the name to zmk-vfx-beacon as CONFIG_BEACON_SPRITE_NAME, whose
sprite_pack.py checks it again. Committed, like assets/README.md: the two
exceptions to the ignore rule on assets/, while the personal files live off the
repository. The name names the subject, so never paste the output into a commit,
a PR or a doc; the messages name neither the file nor the name for the same
reason. Standard library only, macOS /usr/bin/python3 (3.9).
"""
import argparse
import csv
import json
import os
import re
import sys
import unicodedata

NAME_BYTES = 15
CONFIG_ENV = "SPRITE_SENDER_CONFIG"
KATAKANA_RANGES = ((0x2640, 0x2640), (0x2642, 0x2642), (0x30A1, 0x30FC), (0xFF10, 0xFF1A),
                   (0xFF21, 0xFF3A))
LANGUAGES = {1: "ja", 9: "en"}  # the CSV's local_language_id
NOT_THE_CSV = "the name dictionary is not the CSV the sender reads"


class NameError_(ValueError):
    """The file name gives no name (exit 2)."""


class Parser(argparse.ArgumentParser):
    """argparse's errors echo the arguments, and a GIF's path names its subject."""

    def error(self, message):
        self.exit(2, "usage: sprite-name.py [--sender-config <sender.json>] <gif>\n")


def note(why):
    print("sprite-name: %s" % why, file=sys.stderr)


def kconfig_ascii(name):
    """Whether the name row's ASCII font shows the name and Kconfig takes it."""
    return all(" " <= c <= "~" for c in name) and '"' not in name and "\\" not in name and "??" not in name


def from_file_name(file_name):
    """The name as before, from the GIF's file name; NameError_ when it
    gives none."""
    stem = file_name.rsplit(".", 1)[0] if "." in file_name else file_name
    name = stem.strip(" \t")
    if not name:
        raise NameError_("the GIF's file name leaves no name")
    if not kconfig_ascii(name):
        raise NameError_('the GIF\'s file name must be printable ASCII on one line without a '
                         'double quote, a backslash or "??"')
    name = (name[0].upper() + name[1:])[:NAME_BYTES].strip(" \t")
    if not name:
        raise NameError_("the GIF's file name leaves no name")
    return name


def fold_english(name):
    """zmk-vfx-beacon's name_dictionary.fold_english: a trailing gender sign to a
    space and F or M, U+2019 to the ASCII apostrophe, nothing else."""
    if name.endswith("\u2640"):
        name = name[:-1] + " F"
    elif name.endswith("\u2642"):
        name = name[:-1] + " M"
    return name.replace("\u2019", "'")


def shown(text):
    """Whether the HP bar shows a row's name, whole (a cut name would be another
    name), and Kconfig takes it."""
    if len(text.encode("utf-8")) > NAME_BYTES:
        return False
    return kconfig_ascii(text) or all(any(lo <= ord(c) <= hi for lo, hi in KATAKANA_RANGES) for c in text)


def read_species(path, number):
    """({"ja", "en"} of a number, None), or (None, what is wrong with the CSV).
    The whole file is read first, as the sender's tool reads it, so a problem
    shows for every GIF. A name is composed (NFC); a language it lacks gets no
    key."""
    names = {}
    any_name = False
    try:
        with open(path, newline="", encoding="utf-8-sig") as f:
            for row in csv.DictReader(f):
                try:
                    row_number = int(row["pokemon_species_id"])
                    language = LANGUAGES.get(int(row["local_language_id"]))
                    name = row["name"]
                except (KeyError, TypeError, ValueError):
                    return None, NOT_THE_CSV
                if row_number < 1 or not name or language is None:
                    continue
                any_name = True
                if row_number == number:
                    names[language] = unicodedata.normalize("NFC", name)
    except OSError:
        return None, "cannot read the name dictionary"
    except (UnicodeDecodeError, csv.Error):
        return None, NOT_THE_CSV
    if not any_name:
        return None, NOT_THE_CSV
    return names, None


def from_dictionary(gif, config_path):
    """(the name of the GIF or None, why the build falls back to the file name
    or None). A GIF of the collection whose number gives no name that fits is
    no config's fault and gives no reason."""
    match = re.fullmatch(r"([1-9][0-9]*)\.gif", os.path.basename(gif))
    if match is None:
        return None, "the GIF's file name is no number"
    if not config_path:
        return None, "no sender config (--sender-config or $%s)" % CONFIG_ENV
    config_path = os.path.abspath(config_path)
    try:
        with open(config_path, encoding="utf-8-sig") as f:
            config = json.load(f)
    except OSError:
        return None, "cannot read the sender config"
    except (ValueError, RecursionError):
        return None, "the sender config is not JSON"
    csv_path = config.get("names") if isinstance(config, dict) else None
    if not isinstance(csv_path, str) or not csv_path:
        return None, "the sender config names no name dictionary"
    species, problem = read_species(os.path.normpath(os.path.join(os.path.dirname(config_path), csv_path)),
                                    int(match.group(1)))
    if problem:
        return None, problem
    for language in ("ja", "en"):
        if language not in species:
            continue
        name = fold_english(species[language]) if language == "en" else species[language]
        if shown(name):
            return name, None
    return None, None


def main(argv):
    parser = Parser(description="the sprite name of a local build's GIF")
    parser.add_argument("--sender-config", default=os.environ.get(CONFIG_ENV), help="the sprite sender's sender.json")
    parser.add_argument("gif")
    args = parser.parse_args(argv)
    if not args.gif:
        parser.error("")
    gif = os.path.abspath(args.gif)
    name, problem = from_dictionary(gif, args.sender_config)
    if name is None:
        try:
            name = from_file_name(os.path.basename(gif))
        except NameError_ as e:
            note(str(e))
            return 2
    if problem:
        note("ASCII from the file name (%s)" % problem)
    elif name.isascii():
        note("ASCII")
    else:
        note("katakana from the name dictionary")
    sys.stdout.buffer.write((name + "\n").encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
