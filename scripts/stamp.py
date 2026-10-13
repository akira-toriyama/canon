#!/usr/bin/env python3
# The firmware stamp: a build target's inputs digested into the USB
# manufacturer string, so that a Mac can tell from ioreg which inputs a
# device runs (dongle.py check) without opening it.
#
#   stamp.py stamp <board> <shield> <suffix>        the manufacturer string for
#                                                   this tree (zmk-west.sh build)
#   stamp.py verify <build-dir> <board> <shield> <suffix>
#                                                   after a build: the table
#                                                   matches what the build read,
#                                                   and the stamp took
#   stamp.py digest <shield> [--ref REF] [--files]  the digest of this tree, or
#                                                   of REF's commit; --files
#                                                   lists the table
#
# The stamp is `ZMK Project (canon <shield> <12 hex><variant>)`: ZMK's default
# manufacturer kept in front, the build target, the digest, and the variant
# (the image-name suffix of scripts/build-zmk.sh without its leading -sprite,
# so a plain or sprite build has none). 126 characters at most: a USB string
# descriptor's bLength is one byte.
#
# The digest covers only what this repository feeds the build for that
# target, by content, not by commit (a squash merge or an uncommitted build
# digests the same as its tree):
#   - build.yaml, config/west.yml and scripts/zmk-west.sh,
#   - every patches/*/*.patch,
#   - the config/ files ZMK reads for the target, by ZMK's own candidate rule
#     (zmk app/boards/post_boards_shields.cmake, mirrored in inputs()): the
#     .conf of the shield's directory, of every shield-name prefix and of the
#     board, the first overlay, the keymap, what those include from config/,
#     and anything under config/boards/ and config/dts/,
#   - the tree id of the zmk-beacon commit the manifest pins, in place of the
#     SHA (a PR head and its squash commit share the tree). The pin is an
#     input of every target, the halves included: a bump moves all four.
# Comments are left out of the config/ files, build.yaml, west.yml and
# zmk-west.sh (#-lines of .conf except Kconfig's `# CONFIG_X is not set`, which
# assigns n; #-lines of .yml and .sh; C comments of DTS and headers, outside
# string and character literals), and runs of ASCII blanks collapse there: a
# comment-only change to config/ builds the same image (canon #248). A patch
# is hashed as it applies, from its first `diff --git` on, comments and
# whitespace included; so are zmk-west.sh's messages. Upstream (zmk, zephyr,
# zmk-keyboards, the Docker image) is not covered: ZMK is followed at main on
# purpose. ALGORITHM goes into the digest: bump it when this normalization
# changes, and every stamped device reads off-main until it is flashed again.
#
# `verify` fails the build when the table and the build disagree (a config/
# file the build read but the table lacks, or the reverse), so the rule above
# never drifts from ZMK's silently, and when the stamp is not in .config (a
# target without the USB device stack would drop it with a Kconfig warning:
# Zephyr only warns about an assignment that does not take). Reads that leave
# no trace in build.log or zephyr.dts.d (dtlib's /include/, config/boards/,
# config/dts/) are not checked; the table covers the last two by listing them.
#
# Runs in the build container (Linux, python3 of the Docker image) and on
# macOS's /usr/bin/python3 (3.9: no match, no X | Y). Stdlib and git only.

import argparse
import hashlib
import os
import re
import subprocess
import sys

TOP = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))

ALGORITHM = 1
STAMP_PREFIX = "ZMK Project (canon "
STAMP_RE = re.compile(r"^ZMK Project \(canon ([a-z0-9_]+) ([0-9a-f]{12})(\S*)\)$")
UNSTAMPED = "ZMK Project"  # zmk app/Kconfig's USB_DEVICE_MANUFACTURER default
MAX_STRING = 126  # bLength = 2 + 2 * len <= 255
DIGEST_HEX = 12
COMMON = ("build.yaml", "config/west.yml", "scripts/zmk-west.sh")
LEGACY_DIRS = ("config/boards", "config/dts")  # ZMK's extra board and binding roots (zmk app/cmake/modules.cmake)
BEACON = "zmk-beacon"
# The directory of each shield under its module, which ZMK tries first
# (shield_candidate_names). Unknown shields are taken as their own directory;
# verify catches a wrong guess as a file the build read that the table lacks.
SHIELD_DIRS = {"imprint_left": "imprint", "imprint_right": "imprint"}
C_LIKE = (".keymap", ".dtsi", ".overlay", ".h", ".c")
HASH_COMMENTED = (".conf", ".yml", ".yaml", ".sh")
NOT_SET = re.compile(r"^# CONFIG_\w+ is not set\s*$")
BLANKS = re.compile(r"[ \t\r\f\v]+")
INCLUDE = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.M)
INCLUDE_LINE = re.compile(r"[ \t]*#[ \t]*include[ \t]*<[^>\n]*>?")


class Failure(Exception):
    def __init__(self, message, status=1):
        super().__init__(message)
        self.status = status


def git(repo, *args, **kwargs):
    try:
        return subprocess.run(["git", "-C", repo, *args], capture_output=True, check=True, **kwargs).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        err = getattr(e, "stderr", b"") or b""
        raise Failure("git %s in %s failed: %s" % (" ".join(args[:2]), repo, err.decode("utf-8", "replace").strip() or e))


class TreeSource:
    """The files of a work tree or workspace copy, by repository path."""

    def __init__(self, top):
        self.top = top

    def read(self, path):
        try:
            with open(os.path.join(self.top, path), "rb") as f:
                return f.read()
        except OSError:
            return None

    def listdir(self, directory, recursive=False):
        base = os.path.join(self.top, directory)
        if not os.path.isdir(base):
            return []
        if not recursive:
            return sorted(n for n in os.listdir(base) if os.path.isfile(os.path.join(base, n)))
        found = []
        for root, dirs, files in os.walk(base):
            dirs.sort()
            rel = os.path.relpath(root, base)
            found += [n if rel == "." else os.path.join(rel, n) for n in files]
        return sorted(found)


class CommitSource:
    """The files of one commit, through one `git cat-file --batch`."""

    def __init__(self, repo, commit):
        self.repo = repo
        self.commit = commit
        self.paths = set(git(repo, "ls-tree", "-r", "-z", "--name-only", commit).decode().split("\0")) - {""}
        self.proc = subprocess.Popen(["git", "-C", repo, "cat-file", "--batch"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def read(self, path):
        if path not in self.paths:
            return None
        self.proc.stdin.write(("%s:%s\n" % (self.commit, path)).encode())
        self.proc.stdin.flush()
        header = self.proc.stdout.readline().decode().split()
        if len(header) != 3:
            raise Failure("git cat-file could not read %s at %s" % (path, self.commit))
        data = self.proc.stdout.read(int(header[2]))
        self.proc.stdout.read(1)
        return data

    def listdir(self, directory, recursive=False):
        prefix = directory.rstrip("/") + "/"
        names = [p[len(prefix):] for p in self.paths if p.startswith(prefix)]
        return sorted(n for n in names if recursive or "/" not in n)

    def close(self):
        if self.proc.stdin:
            self.proc.stdin.close()
        self.proc.wait()


def pairs(src):
    """build.yaml's targets as (board, shield), as zmk-west.sh pairs reads them."""
    text = (src.read("build.yaml") or b"").decode("utf-8", "replace")
    rows, board, shield = [], "", ""
    for line in text.split("\n"):
        if re.match(r"^\s*#", line):
            continue
        if re.match(r"^\s*-\s", line):
            if board:
                rows.append((board, shield))
            board = shield = ""
        m = re.match(r"^\s*(?:-\s*)?board:\s*(.*?)\s*$", line)
        if m:
            board = m.group(1)
        m = re.match(r"^\s*(?:-\s*)?shield:\s*(.*?)\s*$", line)
        if m:
            shield = m.group(1)
    if board:
        rows.append((board, shield))
    return rows


def board_of(src, shield):
    for board, s in pairs(src):
        if s == shield:
            return board
    raise Failure("shield %s is not in build.yaml" % shield, 2)


def inputs(src, board, shield):
    """The target's input files, as repository paths, sorted."""
    def exists(path):
        return src.read(path) is not None

    # ZMK's names for a qualified board xiao_ble/nrf52840/zmk: BOARD xiao_ble,
    # the board directory xiao_ble, the normalized target xiao_ble_nrf52840_zmk.
    board_name = board.split("/")[0]
    board_names = [board_name, board.replace("/", "_")]
    # shield_candidate_names: the shield's directory, then the prefixes from
    # the longest down, then the shield itself.
    pieces = shield.split("_")
    prefixes = ["_".join(pieces[:i]) for i in range(len(pieces) - 1, 0, -1)]
    names = []
    for n in [SHIELD_DIRS.get(shield, shield)] + prefixes + [shield]:
        if n not in names:
            names.append(n)

    # An old commit of the history walk may lack one of COMMON.
    files = {c for c in COMMON if exists(c)}
    for tree in src.listdir("patches", recursive=True):
        if tree.endswith(".patch") and tree.count("/") == 1:
            files.add("patches/" + tree)
    for d in LEGACY_DIRS:
        files |= {"%s/%s" % (d, n) for n in src.listdir(d, recursive=True)}
    conf, overlays = [], []
    for n in names:
        conf += ["config/%s_%s.conf" % (n, board_name), "config/%s.conf" % n]
        overlays += ["config/%s_%s.overlay" % (n, board_name), "config/%s.overlay" % n]
    conf += ["config/%s.conf" % b for b in board_names] + ["config/default.conf"]
    overlays += ["config/%s.overlay" % b for b in board_names] + ["config/default.overlay"]
    keymaps = ["config/%s.keymap" % n for n in names + board_names]
    files |= {c for c in conf if exists(c)}
    roots = [next((o for o in overlays if exists(o)), None), next((k for k in keymaps if exists(k)), None)]
    todo = [r for r in roots if r]
    while todo:
        path = todo.pop()
        if path in files:
            continue
        files.add(path)
        text = strip_c_comments((src.read(path) or b"").decode("latin-1"))
        for name in INCLUDE.findall(text):
            inc = "config/" + name
            if inc not in files and exists(inc):
                todo.append(inc)
    return sorted(files)


def strip_c_comments(text):
    """text without its C comments; string and character literals and the
    <...> of an include line are kept as they are."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "\n" or i == 0:
            m = INCLUDE_LINE.match(text, i + 1 if c == "\n" else 0)
            if m:
                out.append(text[i:m.end()])
                i = m.end()
                continue
        if c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def normalized(path, data):
    """The bytes that are hashed: the file without its comments."""
    text = data.decode("latin-1")
    ext = os.path.splitext(path)[1]
    if ext in C_LIKE:
        lines = strip_c_comments(text).split("\n")
    elif ext in HASH_COMMENTED:
        lines = [l for i, l in enumerate(text.split("\n"))
                 if not re.match(r"^\s*#", l) or (i == 0 and l.startswith("#!")) or (ext == ".conf" and NOT_SET.match(l))]
    elif ext == ".patch":
        at = 0 if text.startswith("diff --git ") else text.find("\ndiff --git ")
        return (text[at:] if at >= 0 else text).lstrip("\n").encode("latin-1")
    else:
        return data
    lines = [collapse_blanks(l).strip() for l in lines]
    return "\n".join(l for l in lines if l).encode("latin-1")


def collapse_blanks(line):
    """Runs of ASCII blanks outside string literals become one space (a
    removed comment leaves one behind); inside a literal every byte counts.
    Not str.split(): it would also take latin-1's 0x85 and 0xA0, bytes of
    UTF-8."""
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            out.append(line[i:j + 1])
            i = j + 1
        else:
            j = i
            while j < n and line[j] not in "\"'":
                j += 1
            out.append(BLANKS.sub(" ", line[i:j]))
            i = j
    return "".join(out)


def beacon_pin(src):
    """(revision, url) of the zmk-beacon project in config/west.yml, or
    (None, None) for a commit before the pin (2026-09-26)."""
    text = (src.read("config/west.yml") or b"").decode("utf-8", "replace")
    remotes, name, remote, revision, section = {}, None, None, None, None
    for line in text.split("\n"):
        line = line.split("#", 1)[0].rstrip()
        if re.match(r"^\s*remotes:\s*$", line):
            section = "remotes"
        elif re.match(r"^\s*projects:\s*$", line):
            section = "projects"
        m = re.match(r"^\s*-\s*name:\s*[\"']?([^\"'\s]+)", line)
        if m:
            name, remote, revision = m.group(1), None, None
        m = re.match(r"^\s*url-base:\s*[\"']?([^\"'\s]+)", line)
        if m and section == "remotes":
            remotes[name] = m.group(1)
        m = re.match(r"^\s*remote:\s*[\"']?([^\"'\s]+)", line)
        if m:
            remote = m.group(1)
        m = re.match(r"^\s*revision:\s*[\"']?([^\"'\s]+)", line)
        if m:
            revision = m.group(1)
        if section == "projects" and name == BEACON and revision and remote:
            return revision, "%s/%s" % (remotes.get(remote, ""), BEACON)
    return None, None


def manifest_without_pin(data, revision):
    """config/west.yml with the zmk-beacon revision blanked: the tree id
    stands for it, so a re-pin to the same tree keeps the digest."""
    text = data.decode("latin-1")
    if revision:
        text = re.sub(r"^(\s*revision:\s*)%s(\s*(#.*)?)$" % re.escape(revision), r"\1<pin>\2", text, count=1, flags=re.M)
    return text.encode("latin-1")


class BeaconTrees:
    """Tree ids of zmk-beacon commits, from the module's clone; a commit the
    clone lacks is fetched from the manifest's remote (network)."""

    def __init__(self, git_dir):
        self.git_dir = git_dir
        self.cache = {}

    def tree(self, revision, url):
        if revision in self.cache:
            return self.cache[revision]
        if not os.path.isdir(self.git_dir):
            raise Failure("no zmk-beacon clone at %s: build once (scripts/build-zmk.sh), or point ZMK_WS at the workspace" % self.git_dir)
        for attempt in (0, 1):
            try:
                tree = git(self.git_dir, "rev-parse", "--verify", "-q", revision + "^{tree}").decode().strip()
                self.cache[revision] = tree
                return tree
            except Failure:
                if attempt or not url:
                    raise
                git(self.git_dir, "fetch", "-q", url, revision)
        raise AssertionError


def digest(src, board, shield, trees):
    """The 12 hex digest of the target's inputs in src."""
    revision, url = beacon_pin(src)
    lines = ["algorithm %d" % ALGORITHM]
    for path in inputs(src, board, shield):
        data = src.read(path)
        if path == "config/west.yml":
            data = manifest_without_pin(data, revision)
        lines.append("%s %s" % (path, hashlib.sha256(normalized(path, data)).hexdigest()))
    lines.append("%s-tree %s" % (BEACON, trees.tree(revision, url) if revision else "none"))
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()[:DIGEST_HEX]


def variant_of(suffix):
    return re.sub(r"^-sprite(?=[-_]|$)", "", suffix)


def stamp_string(shield, hexdigest, variant):
    s = "%s%s %s%s)" % (STAMP_PREFIX, shield, hexdigest, variant)
    if len(s) > MAX_STRING:
        raise Failure("the stamp %r is %d characters; the USB string descriptor holds %d" % (s, len(s), MAX_STRING))
    return s


def parse_stamp(manufacturer):
    """(shield, digest, variant) of a stamped manufacturer string, else None."""
    m = STAMP_RE.match(manufacturer or "")
    return m.groups() if m else None


def workspace_beacon_git():
    return os.path.join(os.environ.get("ZMK_WS", os.path.expanduser("~/.cache/zmk-canon")), "cfgrepo", "modules", BEACON)


def cmd_stamp(args):
    src = TreeSource(TOP)
    trees = BeaconTrees(os.path.join(TOP, "modules", BEACON))
    print(stamp_string(args.shield, digest(src, args.board, args.shield, trees), variant_of(args.suffix)))
    return 0


def cmd_verify(args):
    src = TreeSource(TOP)
    trees = BeaconTrees(os.path.join(TOP, "modules", BEACON))
    expected = stamp_string(args.shield, digest(src, args.board, args.shield, trees), variant_of(args.suffix))
    table = inputs(src, args.board, args.shield)
    build = os.path.realpath(args.build_dir)
    top = os.path.realpath(TOP) + "/"

    def relative(path):
        path = os.path.realpath(path)
        return path[len(top):] if path.startswith(top) else None

    read = set()
    try:
        with open(os.path.join(build, "build.log"), encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r"^(?:-- )?(?:ZMK Config Kconfig|ZMK Config devicetree overlay|Using keymap file): (\S+)", line)
                if m:
                    read.add(relative(m.group(1)))
        with open(os.path.join(build, "zephyr", "zephyr.dts.d"), encoding="utf-8", errors="replace") as f:
            for token in f.read().replace("\\\n", " ").split():
                if token.endswith(":"):
                    continue
                read.add(relative(token.replace("$$", "$")))
        with open(os.path.join(build, "zephyr", ".config"), encoding="utf-8", errors="replace") as f:
            configured = [l.rstrip("\n") for l in f if l.startswith("CONFIG_USB_DEVICE_MANUFACTURER=")]
    except OSError as e:
        raise Failure("cannot read the build's outputs under %s: %s" % (build, e))
    legacy = tuple(d + "/" for d in LEGACY_DIRS)
    read = {p for p in read if p and p.startswith("config/") and not p.startswith(legacy)}
    tabled = {p for p in table if p.startswith("config/") and p != "config/west.yml" and not p.startswith(legacy)}
    problems = []
    if read - tabled:
        problems.append("the build read config files the stamp's table lacks: %s" % " ".join(sorted(read - tabled)))
    if tabled - read:
        problems.append("the stamp's table holds config files the build did not read: %s" % " ".join(sorted(tabled - read)))
    if configured != ['CONFIG_USB_DEVICE_MANUFACTURER="%s"' % expected]:
        problems.append("zephyr/.config has %s, not the stamp %r (no USB device stack on this target?)"
                        % (configured or "no CONFIG_USB_DEVICE_MANUFACTURER", expected))
    if problems:
        raise Failure("stamp of %s%s not verified:\n  %s\n  The table's rule is in scripts/stamp.py (inputs); the image is not usable until they agree."
                      % (args.shield, args.suffix, "\n  ".join(problems)))
    print("=== STAMP %s%s: %s (%d config files, %d patches)"
          % (args.shield, args.suffix, expected, len(tabled), sum(1 for p in table if p.endswith(".patch"))))
    return 0


def cmd_digest(args):
    trees = BeaconTrees(args.beacon_git or workspace_beacon_git())
    if args.ref:
        commit = git(TOP, "rev-parse", "--verify", args.ref + "^{commit}").decode().strip()
        src = CommitSource(TOP, commit)
    else:
        src = TreeSource(TOP)
    board = board_of(src, args.shield)
    if args.files:
        for path in inputs(src, board, args.shield):
            print(path)
    print(digest(src, board, args.shield, trees))
    if args.ref:
        src.close()
    return 0


def parser():
    p = argparse.ArgumentParser(prog="stamp.py", description="The firmware stamp: a build target's inputs digested into "
                                "the USB manufacturer string (the header of this script).",
                                epilog="Exit status: 0 ok, 1 not verified or a runtime failure, 2 usage.")
    sub = p.add_subparsers(dest="command", metavar="COMMAND")
    sub.required = True
    s = sub.add_parser("stamp", help="print the manufacturer string for this tree (zmk-west.sh build)")
    s.add_argument("board")
    s.add_argument("shield")
    s.add_argument("suffix")
    s.set_defaults(func=cmd_stamp)
    s = sub.add_parser("verify", help="after a build: the table matches what it read, and the stamp is in .config")
    s.add_argument("build_dir")
    s.add_argument("board")
    s.add_argument("shield")
    s.add_argument("suffix")
    s.set_defaults(func=cmd_verify)
    s = sub.add_parser("digest", help="print the target's digest of this tree, or of --ref's commit")
    s.add_argument("shield")
    s.add_argument("--ref", metavar="REF", help="a commit, branch or tag of this repository instead of the work tree")
    s.add_argument("--files", action="store_true", help="list the input table first")
    s.add_argument("--beacon-git", metavar="DIR", help="the zmk-beacon clone that resolves the pin's tree id "
                   "(default: $ZMK_WS/cfgrepo/modules/zmk-beacon)")
    s.set_defaults(func=cmd_digest)
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        return args.func(args)
    except Failure as e:
        print("stamp.py: %s" % e, file=sys.stderr)
        return e.status


if __name__ == "__main__":
    sys.exit(main())
