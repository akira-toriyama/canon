# host/chord/

ZMK ファームから届くチョードを macOS 側で捕まえてアクションを発火する
ホスト側ブリッジ。デーモンは [akira-toriyama/chord](https://github.com/akira-toriyama/chord)
（CGEventTap、Swift 6、TOML 設定）。

## ファイル

- [config.tmpl](./config.tmpl): TOML テンプレート（唯一のソース）。`${ULTRA_LL}` 等の
  修飾子セットは [render-vars.sh](./render-vars.sh) で定義され envsubst で展開。
  `[[bindings]]`（実バインド）と `[[fallbacks]]`（未定義キー効果音）を含む。
- [render.sh](./render.sh): 生成 → `chord --validate` → `~/.config/chord/config.toml`
  へデプロイ → `chord --reload`。**TEMP に生成→検証→OK 時のみ mv** の atomic deploy
  なので壊れた config が稼働中の `config.toml` を上書きしない。chord 未インストール時は
  validate/reload を skip しつつデプロイは実行（インストール後に手動 reload）。
- [render-vars.sh](./render-vars.sh): envsubst 対象の変数定義。修飾子セット 4 個
  (ULTRA_LL / MIRACLE_LM / MEGA_RM / WONDER_RR) ＋ `UNDEFINED_KEY_SOUND_PATH`
  （未定義キー効果音アセットの配置先パス、XDG 既定 + CANON_SOUND_DIR で上書き可）。

## 使い方

```sh
./scripts/render-chord.sh        # 生成 + 検証 + デプロイ + reload
```

config.tmpl を編集したらこれを実行するだけで反映される。`chord` は vnode 監視で
自動 reload もする。

## chord 側のセットアップ（参考）

```sh
brew install akira-toriyama/tap/chord
```

これで CLI と Formula 同梱の `Chord.app` が入る。初回起動 (`open -a Chord`) で
**System Settings → Privacy & Security → Accessibility** の許可ダイアログが出る。
Tap: <https://github.com/akira-toriyama/homebrew-tap>。

ソースから入れたい場合 (開発・先行検証):

```sh
git clone https://github.com/akira-toriyama/chord
cd chord
swift build -c release
./scripts/install-cli.sh        # ~/.local/bin/chord にシンボリックリンク
```

## ショートカット一覧

CI `verify-chord-doc` が同期を検証する（手動編集しない）。bindings の追加・変更は
config.tmpl の `# doc:` 行＋`[[bindings]]` を編集 → `python3 scripts/gen-chord-doc.py`
で再生成。

<!-- AUTO-GENERATED (scripts/gen-chord-doc.py from host/chord/config.tmpl) — do not edit -->

| Chord | Action | Apps |
|---|---|---|
| `ULTRA_LL + C` | タブを左へ（Chrome: Ctrl+Shift+Tab） | com.google.Chrome |
| `ULTRA_LL + C` | タブを左へ（VS Code: Cmd+Shift+[） | com.microsoft.VSCode |
| `ULTRA_LL + V` | タブを右へ（Chrome: Ctrl+Tab） | com.google.Chrome |
| `ULTRA_LL + V` | タブを右へ（VS Code: Cmd+Shift+]） | com.microsoft.VSCode |
| `ULTRA_LL + D` | 前のウィンドウへ（rift フォーカス） | * |
| `ULTRA_LL + F` | 次のウィンドウへ（rift フォーカス） | * |
| `ULTRA_LL + A` | AltTab 起動（全スペース。旧 cmd+ctrl+tab） | * |
| `ULTRA_LL + S` | AltTab 起動（現スペース。旧 alt+tab） | * |
| `kp_1` | Mission Control（全ワークスペースをグリッド表示） | * |
| `Ctrl + B` | ← Left | * |
| `Ctrl + F` | → Right | * |
| `Ctrl + P` | ↑ Up | * |
| `Ctrl + N` | ↓ Down | * |
| `Ctrl + H` | Backspace | * |
| `Ctrl + D` | 前方削除（Forward Delete） | * |
| `Ctrl + J` | Return | * |

<!-- END AUTO-GENERATED -->

## chord 文法の制約メモ

- **L/R 修飾子は side-specific**: [render-vars.sh](./render-vars.sh) で
  `rctrl + ralt + rshift` のように **右側修飾子トークンに固定**している。
  chord v0.2.0 の PR1 (`ed1c032 feat(core)!: side-specific modifier tokens`)
  で `rctrl/ralt/rshift/rcmd` / `lctrl/...` トークンが解禁されたため。
  これにより ZMK ファームの右側修飾子チョードだけが match し、通常タイピングで
  左 modifier 3 個＋同キーを偶発しても発火しない（"設計意図 = ZMK 専用チョード"
  の復活）。
- **同一 input + 別 apps** の per-app 振り分けは「document 順で最初に match した
  binding が発火」。config.tmpl のタブ移動はこの規則で Chrome / VS Code を切替えている。
- **F13–F24・マウス side1/side2・スクロール wheel** は chord でバインド可能（skhd.zig
  では取れなかった領域）。

## 未定義キー効果音フォールバック

4 修飾子セット (ULTRA_LL/MIRACLE_LM/MEGA_RM/WONDER_RR) で実バインド済みの
キー以外を押すと効果音 (`undefined_key.wav`) を鳴らす。chord v0.2.0 PR5 の
`[[fallbacks]]` + `*` ワイルドカードで実装（config.tmpl 末尾）。

- `[[bindings]]` が全 miss した時だけ `[[fallbacks]]` が評価される
  → 既存バインドの誤爆は発生しない
- 音は 1 種共通（旧 skhd 時代の運用と同じ）
- アセット (`undefined_key.wav`) は **dotfiles(chezmoi) 管轄**。本 repo は
  パスを参照するだけ。配備先は `CANON_SOUND_DIR` で上書き可、既定は
  XDG データディレクトリ (`$XDG_DATA_HOME/sounds/` ⇒ 既定 `~/.local/share/sounds/`)
- 未配備でも害なし: `afplay` が静かに失敗するだけ
- フォールバック行は `# doc:` 無し ⇒ ショートカット表 (上記の AUTO-GENERATED) に出さない

## デバッグ

「バインドが効かない」ときの一次切り分け:

```sh
chord --doctor                          # Accessibility 許可 / config / daemon 起動状態
chord --validate --strict ~/.config/chord/config.toml   # drop / warning が出ていないか
tail -f /tmp/chord.log                  # ランタイムログ（chord 既定の出力先）
chord --debug                           # フォアグラウンドで verbose 起動（既存 daemon は --quit で先に止める）
chord --list                            # daemon が解釈中のバインド一覧（text / --json 可）
```

config 内容そのものを覗くなら `~/.config/chord/config.toml`（render.sh のデプロイ先）。
直前版は `.bak` に退避済（壊れた変更の手動復旧用）。
