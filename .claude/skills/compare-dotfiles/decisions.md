# 比較して決めたこと

`compare-dotfiles` の手順2で読む。ここに載っているものは提案し直さない。相手が方式を変えた、
またはこちらの前提が変わったときだけ、「記録ではこうだが」と添えて再提示する。

書き方は1行1件。**何を・いつ・なぜ**。

## 採らないと決めたもの

- **atuin**（2026-09-16）— 5/19 が採用。シェル履歴の検索と同期。今の困りごとに当たらない
- **jujutsu (jj)**（2026-09-16）— 3/19 が採用。git 互換の VCS。乗り換える理由が今はない
- **herdr の tmux 風キーバインド一式**（2026-09-16、Mic92）— 既定のままで困っていない
- **ccusage / ccstatusline**（2026-09-16）— statusline は自作の Nushell 版を使う。表示項目も配色も
  こちらで決めたいため
- **`sed`/`awk` を hook で禁止する**（2026-09-16、lambdalisue）— `tools.md` の推奨で足りている
- **terminal-browser への乗り換え**（2026-09-18）— herdr-browser は上流で deprecated だが、後継は
  まだ入らない。`llm-agents` 版は Electron の署名の封が壊れて起動せず、Release の tarball は
  Gatekeeper の検疫に当たる。バージョンも 0.8.1 対 上流 0.11.1 で追随待ち。加えて後継の herdr
  プラグインは `--target-pane` も `--no-focus` も持たず、`markdown.lua` をそのまま移せない。
  **動いているものを、動かないものに替える段階ではない。** 再検討する条件は「`llm-agents` が
  0.11 系を拾い、かつ `codesign --verify` が通ること」
- **`git-wt` / `git-wtpr` skill**（2026-09-17）— worktrunk（`wt`）を使っているので、持っていない
  CLI の手順書になる。`agents/shared/git-worktrees.md` が既に `wt` を指示している

## 意図的に違うもの

- **Codex のモデル**（2026-09-17）— こちらは `gpt-5.6-sol` + `high`。ryoppippi は `luna` + `max`、
  BurntSushi は `sol` + `max`。土台を上げ、深さは `/model` で足す方針。理由は `codex.nix` のコメント
- **設定ファイルの書き方**（2026-09-16）— Codex / Claude Code / grok の3つとも、共通の Nushell
  スクリプトで「宣言したキーだけマージ」。ryoppippi は Codex だけ同じ方式、Claude Code は別
- **skill の構成**（2026-09-16）— レビューは `codex-review` 1本と PR ゲートの組み合わせ。
  lambdalisue のような `-loop` 変種や `pr-address` は持たない
- **flake の分割方針**（2026-09-17）— apps は `flake/apps.nix` 1枚、helpers は `nix/lib/` と
  modules の外。ryoppippi は `flake/apps/` と `flake/hosts/` に分け helpers を `modules/lib/` に置く
- **ビルドフラグ**（2026-09-17）— darwin でも `--print-build-logs --show-trace` を常時付けない。
  デバッグ時だけ付けるのは `claude/rules/nix.md` の決め事。ryoppippi は常時付与
- **fish キャッシュの削除先**（2026-09-17）— `/tmp` 固定。macOS の `$TMPDIR` は `/var/folders`
  配下で `FISH_CACHE_DIR` と一致せず何も消えない。理由は `nix/flake/apps.nix` のコメント
- **`skill-creator` の模範として挙げる skill**（2026-09-18）— 向こうは `vitest-testing` を2か所で
  挙げるが、その skill に `Key Files` 節も `references/` も**向こうでも**存在しない。こちらは
  実在する `codex-review` と `tdd` を指す。行数や本数は書かない（同じ腐り方をするため）。
  上流に伝えれば差分は消える

## こちらが先行しているもの

- **herdr**（2026-09-16）— 19リポジトリ中、実運用は Mic92 のみ。worktrunk との連携 hook はこちらだけ
- **worktrunk**（2026-09-16）— 採用は kclejeune のみ。herdr の workspace と繋ぐ hook はこちらだけ
- **hunk**（2026-09-17 訂正）— 採用は ryoppippi のみ（1/19）。ただし `home.packages` に置くだけで、
  git からも skill からも呼んでいない。こちらは herdr プラグイン（`herdr-hunk-diff`）として
  ペインに出し、テーマを合わせ、`hunk-review` skill を配るところまでやっている。
  前回「採用ゼロ」と書いたのは誤り
- **Neovim の Markdown プレビュー**（2026-09-16）— live-preview.nvim を herdr のブラウザペインに
  出す構成は、どのリポジトリにもない
