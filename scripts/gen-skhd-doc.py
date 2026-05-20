#!/usr/bin/env python3
"""host/skhd/skhdrc.tmpl から host/skhd/README.md のショートカット表を生成。

skhdrc.tmpl の各バインド直前の `# doc: <動作>` 行を唯一のソースとし、
README.md 内の AUTO-GENERATED マーカー間（markdown 表）を書き換える。
ショートカット表記はバインド行から導出（`${ULTRA_LL} - ${X_C}` → `ULTRA_LL + C`、
`ctrl - b` → `Ctrl + B`）。

  python3 scripts/gen-skhd-doc.py          # 生成して README を更新
  python3 scripts/gen-skhd-doc.py --check   # 差分があれば exit 1 (CI 用)

stdlib のみ。リポジトリルートからの相対パスで動く。
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TMPL = ROOT / "host" / "skhd" / "skhdrc.tmpl"
README = ROOT / "host" / "skhd" / "README.md"

BEGIN = "<!-- AUTO-GENERATED (scripts/gen-skhd-doc.py from host/skhd/skhdrc.tmpl) — do not edit -->"
END = "<!-- END AUTO-GENERATED -->"

DOC_RE = re.compile(r"^#\s*doc:\s*(.+?)\s*$")
# 修飾子は任意（`${X_1} : cmd` のような単押しキーも有効なバインド）。
# mods があれば `<mods> - <key>`、無ければ `<key>` のみ。mods トークンに
# `-` は現れない（区切りの ` - ` のみが `-`）ため [^-] で前段を限定する。
BIND_RE = re.compile(r"^(?:(?P<mods>[^-]+?)\s*-\s*)?(?P<key>\S+)\s*(?:\[|:)")
_MOD = {"ctrl": "Ctrl", "alt": "Alt", "shift": "Shift", "cmd": "Cmd",
        "rctrl": "RCtrl", "ralt": "RAlt", "rshift": "RShift", "rcmd": "RCmd"}


def _unvar(tok: str) -> str:
    """`${ULTRA_LL}`→`ULTRA_LL`、`${X_C}`→`C`、素の修飾子は表記正規化。"""
    m = re.fullmatch(r"\$\{X_([^}]+)\}", tok)
    if m:
        return m.group(1)
    m = re.fullmatch(r"\$\{([^}]+)\}", tok)
    if m:
        return m.group(1)
    return _MOD.get(tok, tok.upper() if len(tok) == 1 else tok)


def chord(line: str) -> str:
    m = BIND_RE.match(line)
    if not m:
        raise SystemExit(f"skhdrc.tmpl: バインド行を解釈できない: {line!r}")
    key = _unvar(m.group("key"))
    if not m.group("mods"):
        return key  # 単押しキー（修飾子なし）
    mods = " + ".join(_unvar(t.strip()) for t in m.group("mods").split("+"))
    return f"{mods} + {key}"


def build_block() -> str:
    rows: list[tuple[str, str]] = []
    pending: str | None = None
    pending_ln = 0
    for ln, raw in enumerate(TMPL.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if m := DOC_RE.match(line):
            if pending is not None:
                print(
                    f"warning: skhdrc.tmpl:{pending_ln} `# doc: {pending}` の直後に"
                    f" バインドが無いまま {ln} 行目で次の doc 行。無視されます。",
                    file=sys.stderr,
                )
            pending = m.group(1)
            pending_ln = ln
            continue
        if pending is None or not line or line.startswith((".define", "#")):
            continue
        rows.append((chord(line), pending))
        pending = None
    if pending is not None:
        print(
            f"warning: skhdrc.tmpl:{pending_ln} `# doc: {pending}` の後に"
            " バインドが無いまま終端。無視されます。",
            file=sys.stderr,
        )
    if not rows:
        raise SystemExit("skhdrc.tmpl: `# doc:` 付きバインドが見つからない")
    out = ["| ショートカット | 動作 |", "| --- | --- |"]
    out += [f"| `{c}` | {d} |" for c, d in rows]
    return "\n".join(out)


def render() -> str:
    text = README.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        raise SystemExit("README.md に AUTO-GENERATED マーカーが無い")
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{build_block()}\n{END}{tail}"


def main() -> int:
    new = render()
    if "--check" in sys.argv[1:]:
        if new != README.read_text(encoding="utf-8"):
            print(
                "host/skhd/README.md が skhdrc.tmpl と同期していません。\n"
                "  python3 scripts/gen-skhd-doc.py を実行してコミットしてください。",
                file=sys.stderr,
            )
            return 1
        print("skhd doc は同期済み")
        return 0
    README.write_text(new, encoding="utf-8")
    print(f"updated {README.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
