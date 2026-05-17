# skhd ブリッジ

ZMK が送る「修飾キーの組み合わせ（chord）＋ base key」を macOS 側で
[skhd.zig](https://github.com/jackielii/skhd.zig) が受けて操作に変換する。

- 単一ソース: [`skhdrc.tmpl`](skhdrc.tmpl)（`.define` で共通コマンド、`@ref`
  で参照、`["App" : cmd]` でアプリ別）
- [`render.sh`](render.sh) が変数を `envsubst` で置換 → 検証 →
  `~/.config/skhd/skhdrc` へ反映・reload（検証 NG なら反映しない）
- 更新手順: `skhdrc.tmpl` を編集 → `./render.sh`

## 修飾セット（[`render.sh`](render.sh) で定義）

| 名前      | 構成                        | 備考 |
| --------- | --------------------------- | ---- |
| `ULTRA_LL` | 右 Ctrl + 右 Alt + 右 Shift |
| `MIRACLE_LM` | 右 Ctrl + 右 Cmd + 右 Shift |
| `MEGA_RM` | 右 Ctrl + 右 Cmd + 右 Alt   |
| `WONDER_RR` | 右 Cmd + 右 Alt + 右 Shift  |

## ショートカット一覧

`skhdrc.tmpl` が唯一のソース。下表は `scripts/gen-skhd-doc.py` が自動生成し、
CI `verify-skhd-doc` が同期を検証する（手動編集しない）。emacs 風 Ctrl は
全アプリ共通・`Shift+Ctrl` はパススルー・`Ctrl+A/E` は非搭載（macOS ネイティブ）。

<!-- AUTO-GENERATED (scripts/gen-skhd-doc.py from host/skhd/skhdrc.tmpl) — do not edit -->
| ショートカット | 動作 |
| --- | --- |
| `ULTRA_LL + C` | タブを左へ（Chrome: Ctrl+Shift+Tab / VS Code: Cmd+Shift+[） |
| `ULTRA_LL + V` | タブを右へ（Chrome: Ctrl+Tab / VS Code: Cmd+Shift+]） |
| `ULTRA_LL + D` | 前のウィンドウへ（rift フォーカス） |
| `ULTRA_LL + F` | 次のウィンドウへ（rift フォーカス） |
| `ULTRA_LL + A` | AltTab 起動（全スペース。旧 cmd+ctrl+tab） |
| `ULTRA_LL + S` | AltTab 起動（現スペース。旧 alt+tab） |
| `Ctrl + B` | ← Left |
| `Ctrl + F` | → Right |
| `Ctrl + P` | ↑ Up |
| `Ctrl + N` | ↓ Down |
| `Ctrl + H` | Backspace |
| `Ctrl + D` | 前方削除（Forward Delete） |
| `Ctrl + J` | Return |
<!-- END AUTO-GENERATED -->
