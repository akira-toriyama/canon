#!/usr/bin/env python3
"""config/eiji_macros.dtsi から keymap_drawer.config.yaml の en_* ブロックを生成。

eiji_macros.dtsi の各 `EN_MACRO(name, KEY)  // disp:[X]` 行を唯一のソースとし、
keymap_drawer.config.yaml 内の AUTO-GENERATED マーカー間を書き換える。

  python3 scripts/gen-eiji-drawer-map.py          # 生成して yaml を更新
  python3 scripts/gen-eiji-drawer-map.py --check   # 差分があれば exit 1 (CI 用)

stdlib のみ。リポジトリルートからの相対パスで動く。
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

SECTION_RE = re.compile(r"^\s*//\s*(EIJI 切替 →.*?（.*?_LAYER 用）)\s*$")
MACRO_RE = re.compile(
    r"^\s*EN_MACRO\(\s*([A-Za-z0-9_]+)\s*,\s*[A-Za-z0-9_]+(?:\([A-Za-z0-9_]+\))?\s*\)\s*//\s*disp:\[(.*)\]\s*$"
)


def yaml_value(ch: str) -> str:
    """表示文字を YAML スカラとして安全に引用する。"""
    if ch == "'":
        return '"\'"'
    if ch == "\\":
        return "'\\'"
    return f"'{ch}'"


def build_block() -> str:
    """dtsi を読んで AUTO-GENERATED マーカー間に入れる本文を組み立てる。"""
    sections: list[tuple[str, list[tuple[str, str]]]] = []
    for line in DTSI.read_text(encoding="utf-8").splitlines():
        if m := SECTION_RE.match(line):
            sections.append((m.group(1), []))
            continue
        if m := MACRO_RE.match(line):
            if not sections:
                raise SystemExit("eiji_macros.dtsi: セクションコメント前に EN_MACRO が出現")
            name, ch = m.group(1), m.group(2)
            if len(ch) != 1:
                raise SystemExit(
                    f"eiji_macros.dtsi: EN_MACRO({name}) の disp:[{ch}] は"
                    f"1文字でなければならない（幅={len(ch)}）"
                )
            sections[-1][1].append((name, ch))

    entries = [(f'"&{name}":', yaml_value(ch)) for _, s in sections for name, ch in s]
    if not entries:
        raise SystemExit("eiji_macros.dtsi: disp:[X] 付きの EN_MACRO が見つからない")
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
        raise SystemExit("keymap_drawer.config.yaml に AUTO-GENERATED マーカーが無い")
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{build_block()}\n{END}{tail}"


def main() -> int:
    new = render()
    if "--check" in sys.argv[1:]:
        if new != YAML.read_text(encoding="utf-8"):
            print(
                "keymap_drawer.config.yaml が eiji_macros.dtsi と同期していません。\n"
                "  python3 scripts/gen-eiji-drawer-map.py を実行してコミットしてください。",
                file=sys.stderr,
            )
            return 1
        print("eiji_* mapping は同期済み")
        return 0
    YAML.write_text(new, encoding="utf-8")
    print(f"updated {YAML.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
