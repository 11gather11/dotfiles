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
- **`git-wt` / `git-wtpr` skill**（2026-09-17）— worktrunk（`wt`）を使っているので、持っていない
  CLI の手順書になる。`agents/shared/git-worktrees.md` が既に `wt` を指示している

## 意図的に違うもの

- **Codex のモデル**（2026-09-17、2026-11-06 訂正）— こちらは `gpt-6.1-sol` + `medium`。ryoppippi は
  luna を既定にし、sol high が指揮して luna max のサブエージェントが実装する。土台を上げ、深さは
  `/model` で足す方針。理由は `codex.nix` のコメント
- **設定ファイルの書き方**（2026-09-16、2026-11-06 訂正）— Codex と Claude Code を、共通の Nushell
  スクリプトで「宣言したキーだけマージ」（grok はもう無い）。ryoppippi は Codex だけ同じ方式
- **skill の構成**（2026-09-16）— レビューは `codex-review` 1本と PR ゲートの組み合わせ。
  lambdalisue のような `-loop` 変種や `pr-address` は持たない
- **flake の分割方針**（2026-09-17）— apps は `flake/apps.nix` 1枚、helpers は `nix/lib/` と
  modules の外。ryoppippi は `flake/apps/` と `flake/hosts/` に分け helpers を `modules/lib/` に置く
- **ビルドフラグ**（2026-09-17）— darwin でも `--print-build-logs --show-trace` を常時付けない。
  デバッグ時だけ付けるのは `claude/rules/nix.md` の決め事。ryoppippi も `bdd14a13` でやめ、差は消えた
- **fish キャッシュの削除先**（2026-09-17）— `/tmp` 固定。macOS の `$TMPDIR` は `/var/folders`
  配下で `FISH_CACHE_DIR` と一致せず何も消えない。理由は `nix/flake/apps.nix` のコメント。
  ryoppippi は `f4cca74c` で実行時キャッシュそのものをやめ、hook を Nix で conf.d に生成している
  （2026-11-06 確認。乗り換えるかは未検討）
- **code-comments の既定**（2026-11-06）— ryoppippi は「既定はコメントを書かない、JSDoc は公開 API だけ」
  （`2dce2929`、`44a7911c`）。こちらはユーザーの方針（why を書く、export に JSDoc）なので寄せない
- **Execution Safety を2ルールで持つ**（2026-09-18）— 向こうは1行に畳んでいる。こちらが分けている
  のは2つ目（外部への効果は1回ずつ承認が要る／1回の承認は次に及ばない）が効くから。理由は `81103a04`
- **`git-staging.md` の巻き込み禁止の理由**（2026-09-18）— 向こうは `codex.nix` を名指しするが、
  こちらは「公開リポジトリでは commit は publish」と書く。具体ファイル名を書かない方針と整合。
  flake の staging も「**新規**ファイルだけ必要、既存の編集は不要」とこちらが正確。理由は `f6192394`
- **`git-worktrees.md` は worktrunk 前提**（2026-09-18）— 向こうは全項目が `git-wt`/`git-wtpr` 前提。
  理由は `f707faaf`（半年で `git wt` 1回、`git wtpr` 0回。維持されていたが使われていなかった）
- **`codex/AGENTS.md` のシェルは Fish**（2026-09-18）— 向こうは Zsh。こちらに `programs.zsh` は無く、
  `rules/tools.md` も Fish 前提。ただし理由の記録は無いので、Zsh を整えるなら再検討の余地あり
- **Codex の Browser プラグインは宣言できていない**（2026-09-18）— Browser Automation 節は採用済み。
  ただし `codex.nix` が宣言しているのは `plugins."github@openai-curated"` だけで、Browser は
  **Desktop アプリ側で手動インストールしたもの**。ryoppippi も同じ状態（向こうの宣言も github 1つ）。
  つまり両方とも「指示文は Browser を前提にしているが、構成には現れない」。宣言する方法が分かれば埋めたい
- **コミット本文に詳細を書く一文**（2026-09-18）— 向こうは「commit message に書け」だけ。こちらは
  「what changed and why を書く」まで残す。他にそれを求める場所が無いため
- **`skill-creator` の模範として挙げる skill**（2026-09-18）— 向こうは `vitest-testing` を2か所で
  挙げるが、その skill に `Key Files` 節も `references/` も**向こうでも**存在しない。こちらは
  実在する `codex-review` と `tdd` を指す。行数や本数は書かない（同じ腐り方をするため）。
  上流に伝えれば差分は消える

## 採ったもの

- **git hook の switch を main 限定**（2026-11-06、提案 A）— `8ef5b706`。hook は全 worktree で共有され、
  worker の commit がマージ前の構成を適用していた
- **zsh の `NO_EQUALS`**（2026-11-06、提案 C の一部）— `echo ===` が「== not found」で落ちていた

## 保留中の提案（2026-11-06）

採否を決めたら上の節へ移す。

- **B. 調べものの委譲先を native subagent に**（`aab3f38f`）— delegate-work.md が `codex exec` を指している
- **C. `fish -lc` の指示を外す**（`2d0203f4`）— 同じ commit の zsh `NO_EQUALS` は 2026-11-06 に採用済み
- **D. worktree の subagent には1回1コマンド**（`2d0203f4`）
- **E. comma の非対話ラッパー**（`75dc7e78`）
- **F. skill の drift 解消** — tdd、vitest（snapshot 禁止）、fix-ci、merge-main、pr-apply-review、
  create-pr、commit を寄せる。council は削除、create-commits-and-push は統合。名前は変えない
- **G. How to Work 節と description の型**（`65fd3123`、`fada853f`）
- **H. nix.md を agents/shared に移して Codex にも配る**

## こちらが先行しているもの

- **herdr**（2026-09-16）— 19リポジトリ中、実運用は Mic92 のみ。worktrunk との連携 hook はこちらだけ
- **worktrunk**（2026-09-16）— 採用は kclejeune のみ。herdr の workspace と繋ぐ hook はこちらだけ
- **hunk**（2026-09-17 訂正）— 採用は ryoppippi のみ（1/19）。ただし `home.packages` に置くだけで、
  git からも skill からも呼んでいない。こちらはテーマを合わせ、`hunk-review` skill を配るところまで
  やっている（herdr プラグインの `herdr-hunk-diff` は 2026-09-18 に外した）。
  前回「採用ゼロ」と書いたのは誤り
- **Neovim の Markdown プレビュー**（2026-09-16）— live-preview.nvim を herdr のブラウザペインに
  出す構成は、どのリポジトリにもない
