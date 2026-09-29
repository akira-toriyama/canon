#!/usr/bin/env python3
"""Generate the en_* labels of keymap_drawer.config.yaml from config/eiji_macros.dtsi.

Each `EN_MACRO(name, KEY)  // disp:[X]` line of eiji_macros.dtsi is the single
source. The script rewrites the lines between the AUTO-GENERATED markers of
keymap_drawer.config.yaml, with each `// ... (<NAME>_LAYER)` section comment as
a heading.

  python3 scripts/gen-eiji-drawer-map.py          # rewrite the block
  python3 scripts/gen-eiji-drawer-map.py --check  # exit 1 when out of sync (CI)

Python stdlib only; paths are resolved from the repository root.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DTSI = ROOT / "config" / "eiji_macros.dtsi"
YAML = ROOT / "keymap_drawer.config.yaml"

BEGIN = "    # === AUTO-GENERATED (scripts/gen-eiji-drawer-map.py from config/eiji_macros.dtsi) — do not edit ==="
END = "    # === END AUTO-GENERATED ==="

SECTION_RE = re.compile(r"^\s*//\s*(.+\([A-Z0-9_]+_LAYER\))\s*$")
MACRO_RE = re.compile(
    r"^\s*EN_MACRO\(\s*([A-Za-z0-9_]+)\s*,\s*[A-Za-z0-9_]+(?:\([A-Za-z0-9_]+\))?\s*\)\s*//\s*disp:\[(.*)\]\s*$"
)


def yaml_value(ch: str) -> str:
    """Quote a label as a YAML scalar: single quotes, double quotes around '."""
    if ch == "'":
        return '"\'"'
    if ch == "\\":
        return "'\\'"
    return f"'{ch}'"


def build_block() -> str:
    sections: list[tuple[str, list[tuple[str, str]]]] = []
    for line in DTSI.read_text(encoding="utf-8").splitlines():
        if m := SECTION_RE.match(line):
            sections.append((m.group(1), []))
            continue
        if m := MACRO_RE.match(line):
            if not sections:
                raise SystemExit("eiji_macros.dtsi: EN_MACRO before the first section comment")
            name, ch = m.group(1), m.group(2)
            if len(ch) != 1:
                raise SystemExit(
                    f"eiji_macros.dtsi: EN_MACRO({name}) has disp:[{ch}];"
                    f" a label is one character (got {len(ch)})"
                )
            sections[-1][1].append((name, ch))

    entries = [(f'"&{name}":', yaml_value(ch)) for _, s in sections for name, ch in s]
    if not entries:
        raise SystemExit("eiji_macros.dtsi: no EN_MACRO with a disp:[X] label")
    width = max(len(k) for k, _ in entries)

    out: list[str] = []
    for i, (title, items) in enumerate(sections):
        if i:
            out.append("")
        out.append(f"    # {title}")
        for name, ch in items:
            key = f'"&{name}":'
            out.append(f"    {key.ljust(width)} {yaml_value(ch)}")
    return "\n".join(out)


def render() -> str:
    text = YAML.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        raise SystemExit("keymap_drawer.config.yaml: AUTO-GENERATED markers not found")
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{build_block()}\n{END}{tail}"


def main() -> int:
    new = render()
    if "--check" in sys.argv[1:]:
        if new != YAML.read_text(encoding="utf-8"):
            print(
                "keymap_drawer.config.yaml is out of sync with config/eiji_macros.dtsi.\n"
                "  Run python3 scripts/gen-eiji-drawer-map.py and commit the result.",
                file=sys.stderr,
            )
            return 1
        print("en_* labels in sync")
        return 0
    YAML.write_text(new, encoding="utf-8")
    print(f"updated {YAML.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
