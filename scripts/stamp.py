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
# (the image-name suffix of scripts/build-zmk.sh without -sprite, so a plain
# or sprite build has none). 126 characters at most: a USB string descriptor's
# bLength is one byte.
#
# The digest covers only what this repository feeds the build for that
# target, by content, not by commit (a squash merge or an uncommitted build
# digests the same as its tree):
#   - build.yaml, config/west.yml and scripts/zmk-west.sh,
#   - patches/<tree>/*.patch for the trees zmk-west.sh patches,
#   - the config/ files ZMK reads for the target, by ZMK's own candidate rule
#     (zmk app/boards/post_boards_shields.cmake): the .conf of every
#     shield-name prefix and of the board, the first overlay, the keymap, and
#     what those include from config/,
#   - the tree id of the zmk-beacon commit the manifest pins (a PR head and
#     its squash commit share it).
# Comments are left out (#-lines of .conf, .yml and .sh, C comments of DTS and
# headers, a patch's text before its first diff): a comment-only change built
# the same image (canon #242, #248). Upstream (zmk, zephyr, zmk-keyboards, the
# Docker image) is not covered: ZMK is followed at main on purpose.
#
# `verify` fails the build when the table and the build disagree (a config/
# file the build read but the table lacks, or the reverse), so the rule above
# never drifts from ZMK's silently, and when the stamp is not in .config (a
# target without the USB device stack would drop it with a Kconfig warning).
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

STAMP_PREFIX = "ZMK Project (canon "
STAMP_RE = re.compile(r"^ZMK Project \(canon ([a-z0-9_]+) ([0-9a-f]{12})(\S*)\)$")
UNSTAMPED = "ZMK Project"  # zmk app/Kconfig's USB_DEVICE_MANUFACTURER default
MAX_STRING = 126  # bLength = 2 + 2 * len <= 255
DIGEST_HEX = 12
TREES = ("zmk", "zephyr")  # the patched projects: zmk-west.sh's TREES
COMMON = ("build.yaml", "config/west.yml", "scripts/zmk-west.sh")
BEACON = "zmk-beacon"
C_LIKE = (".keymap", ".dtsi", ".overlay", ".h", ".c")
HASH_COMMENTED = (".conf", ".yml", ".yaml", ".sh")
INCLUDE = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.M)


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

    def listdir(self, directory):
        try:
            names = os.listdir(os.path.join(self.top, directory))
        except OSError:
            return []
        return sorted(n for n in names if os.path.isfile(os.path.join(self.top, directory, n)))


class CommitSource:
    """The files of one commit, through one `git cat-file --batch`."""

    def __init__(self, repo, commit):
        self.repo = repo
        self.commit = commit
        self.paths = set(git(repo, "ls-tree", "-r", "--name-only", commit).decode().split("\n")) - {""}
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

    def listdir(self, directory):
        prefix = directory.rstrip("/") + "/"
        return sorted(p[len(prefix):] for p in self.paths if p.startswith(prefix) and "/" not in p[len(prefix):])

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
    pieces = shield.split("_")
    prefixes = ["_".join(pieces[:i]) for i in range(1, len(pieces) + 1)]
    board_names = [board.split("/")[0]] + ([board] if "/" not in board else [])
    def exists(path):
        return src.read(path) is not None

    # An old commit of the history walk may lack one of COMMON.
    files = {c for c in COMMON if exists(c)}
    for tree in TREES:
        files |= {"patches/%s/%s" % (tree, n) for n in src.listdir("patches/" + tree) if n.endswith(".patch")}

    conf = []
    for p in prefixes:
        if "/" not in board:
            conf.append("config/%s_%s.conf" % (p, board))
        conf.append("config/%s.conf" % p)
    conf += ["config/%s.conf" % b for b in board_names] + ["config/default.conf"]
    files |= {c for c in conf if exists(c)}
    overlays = []
    for p in prefixes:
        if "/" not in board:
            overlays.append("config/%s_%s.overlay" % (p, board))
        overlays.append("config/%s.overlay" % p)
    overlays += ["config/%s.overlay" % b for b in board_names] + ["config/default.overlay"]
    keymaps = ["config/%s.keymap" % n for n in prefixes + board_names]
    roots = [next((o for o in overlays if exists(o)), None), next((k for k in keymaps if exists(k)), None)]
    todo = [r for r in roots if r]
    while todo:
        path = todo.pop()
        if path in files:
            continue
        files.add(path)
        for name in INCLUDE.findall((src.read(path) or b"").decode("utf-8", "replace")):
            inc = "config/" + name
            if inc not in files and exists(inc):
                todo.append(inc)
    return sorted(files)


def strip_c_comments(text):
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
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
        lines = [l for i, l in enumerate(text.split("\n")) if not re.match(r"^\s*#", l) or (i == 0 and l.startswith("#!"))]
    elif ext == ".patch":
        at = 0 if text.startswith("diff --git ") else text.find("\ndiff --git ")
        lines = (text[at:] if at >= 0 else text).split("\n")
    else:
        return data
    # Runs of blanks collapse too: a removed comment leaves one behind.
    return "\n".join(" ".join(l.split()) for l in lines if l.strip()).encode("latin-1")


def beacon_pin(src):
    """(revision, url) of the zmk-beacon project in config/west.yml."""
    text = (src.read("config/west.yml") or b"").decode("utf-8", "replace")
    remotes, name, remote, revision, section = {}, None, None, None, None
    for line in text.split("\n"):
        line = line.split("#", 1)[0].rstrip()
        if re.match(r"^\s*remotes:\s*$", line):
            section = "remotes"
        elif re.match(r"^\s*projects:\s*$", line):
            section = "projects"
        m = re.match(r"^\s*-\s*name:\s*(\S+)", line)
        if m:
            name, remote, revision = m.group(1), None, None
        m = re.match(r"^\s*url-base:\s*(\S+)", line)
        if m and section == "remotes":
            remotes[name] = m.group(1)
        m = re.match(r"^\s*remote:\s*(\S+)", line)
        if m:
            remote = m.group(1)
        m = re.match(r"^\s*revision:\s*(\S+)", line)
        if m:
            revision = m.group(1)
        if section == "projects" and name == BEACON and revision and remote:
            return revision, "%s/%s" % (remotes.get(remote, ""), BEACON)
    return None, None  # a commit before the pin (2026-09-26)


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
    lines = []
    for path in inputs(src, board, shield):
        data = src.read(path)
        lines.append("%s %s" % (path, hashlib.sha256(normalized(path, data)).hexdigest()))
    revision, url = beacon_pin(src)
    lines.append("%s-tree %s" % (BEACON, trees.tree(revision, url) if revision else "none"))
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()[:DIGEST_HEX]


def variant_of(suffix):
    return suffix.replace("-sprite", "", 1)


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
                read.add(relative(token))
        with open(os.path.join(build, "zephyr", ".config"), encoding="utf-8", errors="replace") as f:
            configured = [l.rstrip("\n") for l in f if l.startswith("CONFIG_USB_DEVICE_MANUFACTURER=")]
    except OSError as e:
        raise Failure("cannot read the build's outputs under %s: %s" % (build, e))
    read = {p for p in read if p and p.startswith("config/")}
    tabled = {p for p in table if p.startswith("config/") and p != "config/west.yml"}
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
