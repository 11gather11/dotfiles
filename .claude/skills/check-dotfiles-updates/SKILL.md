---
name: check-dotfiles-updates
description: Show new commits on the watched dotfiles repositories since each one was last checked, then compare how they configure the tools this repository also uses. Use when the user asks to check upstream dotfiles, catch up on what others changed, or look for tools and settings worth adopting.
---

# Check watched dotfiles updates

このリポジトリは自分用に育てていく前提で、他人の dotfiles は**最新の動向を知るための情報源**として監視する。取り込みは前提ではない。

- 監視対象: `watchlist.json`（このディレクトリ、git 管理）
- 最終確認日: `last-check.json`（このディレクトリ、git 管理外）。リポジトリごとに ISO 8601 で保持
- 報告先: `artifact.json`（このディレクトリ、git 管理外）。毎回同じページを更新するための URL を保持

## 手順

1. `watchlist.json` と `last-check.json` を読む。

   引数でリポジトリ名（`Mic92/dotfiles` など）が渡された場合はそれだけを対象にする。
   渡されなければ watchlist 全件。

2. 各リポジトリのローカル clone を用意する。パスは `$(ghq root)/github.com/<repo>`。

   **GitHub API では代替しない。** commit 一覧だけなら API でも取れるが、手順6の「このツールを
   何人が使っているか」は全ファイルを横断 grep しないと数えられず、コード検索 API は結果が
   不安定でレート制限にもかかる（実際に誤検出とレート制限の両方を踏んでいる）。ローカルに
   置けば `rg` で確実に数えられる。19 リポジトリで 270MB 前後、全件 fetch で 20 秒程度。

   無ければ blobless clone で取得する（履歴のメタデータは全部持ちつつ、過去版のファイル実体は
   取らないので軽い。現在のファイルは checkout されるので grep できる）:

   ```bash
   git clone --filter=blob:none "https://github.com/<repo>" "$(ghq root)/github.com/<repo>"
   ```

   あれば更新する:

   ```bash
   git -C "$(ghq root)/github.com/<repo>" fetch origin --quiet
   ```

   デフォルトブランチは固定しない。`git -C <path> symbolic-ref refs/remotes/origin/HEAD` で解決する
   （`main` とは限らない）。

3. `last-check.json` にそのリポジトリの記録が無ければ、初回として**直近 30 日**を対象にする。
   その旨を報告し、別の起点を指定したいか聞く。

4. 最終確認日以降の commit を取得する。依存更新 bot が大半を占めるので、**必ず除外してから**件数を数える:

   ```bash
   git -C <path> log <default-branch> --since="<SINCE>" --no-merges \
     --pretty=format:'%h%x09%aI%x09%an%x09%s' \
     | rg -v '\[bot\]|renovate|dependabot' \
     | rg -v 'update flake input|update llm-agents|chore\(deps\)|: [0-9.]+ -> [0-9.]+'
   ```

   全体件数と除外後の件数の両方を報告する。

5. 提示する。**リポジトリごとに**、除外後の件数で出し分ける:
   - **0 件**: 「新着なし」とだけ書く
   - **30 件以下**: commit を一覧（`%h %aI %s`）。気になるものは `git show --stat` で深掘り
   - **30 件超**: 件数を報告し、領域別（darwin / nvim / skills / shell / nix 基盤 など）に分類した表を出してから、詳細を見たい領域を聞く

   全リポジトリを見たあと、**横断的に「新しく登場したツール」を拾って報告する**。
   複数人が同じツールを入れ始めていれば、それが動向のシグナルになる。

6. **ツールを提案する。** ここが監視の主目的なので、遠慮せず踏み込む。

   乗り換えの commit は最も強いシグナルなので、明示的に拾う:

   ```bash
   git -C <path> log <default-branch> --since="<SINCE>" --no-merges \
     --pretty=format:'%h%x09%s' \
     --grep='replace' --grep='instead of' --grep='in favou\?r of' \
     --grep='migrate' --grep='switch to' --grep='drop' -i
   ```

   採用の広がりは、こちらに無いツールを watchlist 全体で数えて測る:

   ```bash
   for p in <各 clone>; do rg -l --no-messages '<tool>' "$p" -g '!.git' >/dev/null && echo "$p"; done
   ```

   提案は次の3種類。いずれも**このリポジトリの現状と突き合わせてから**出す:
   - **未導入の新ツール** — 複数人が採用していて、こちらに無いもの
   - **乗り換え候補** — こちらが使っているツールから、他の人が乗り換えた先があるもの
     （例: 「A を使っているが、N 人が B へ移行している」）
   - **重複・陳腐化** — 同じ役割のツールを二重に持っている、あるいは採用者が減っているもの

   各提案には「**誰が使っているか（何/19）**」「**何を解決するか**」「**乗り換えコスト**」を添える。
   根拠なく流行りを勧めない。採用者が 1 人だけなら、そう明示する。

7. **同じツールの設定と仕組みを比べる。** 手順6が「何を入れているか」なら、ここは「同じものを
   どう設定しているか」を見る。新しいツールより、こちらが毎日使っているツールの設定のほうが
   効く場面は多い。

   対象は**両者が持っているツール**に絞る。相手が持っていないものを比べても意味がない:

   ```bash
   # 例: Codex / Claude Code / herdr / Neovim のモジュールを持つ相手を探す
   for p in <各 clone>; do fd -i '<tool>' "$p" -t f -t d -E .git | head -1 | rg -q . && echo "$p"; done
   ```

   見つかった相手について、次の3点を比べる。差分が出たものだけ報告する:
   - **設定値** — こちらが宣言していないキー、値が違うキー（モデル、effort、機能フラグなど）
   - **書き込み方** — 生成／コピー／マージのどれか。アプリ自身が書くファイルをどう守っているか
   - **skill や指示文** — 同名の skill、`AGENTS.md`、共有断片があれば中身を比べる

   報告は「相手の値 / こちらの値 / なぜ違うか」の形にする。**相手の値をそのまま勧めない。**
   こちらの設定にコメントで理由が書いてあるなら、それを読んでから「その理由はまだ有効か」を問う。

8. **結果を Artifact のページにまとめる。** チャットには要約（件数、目についた変更、提案の見出し）
   だけを書き、詳細は毎回ページに置く。載せるのは手順4〜7の全部:
   - リポジトリごとの新着 commit（除外前後の件数と一覧。30件超は領域別の表）
   - ツールの採用状況（何/19、誰が使っているか、こちらの有無）
   - 乗り換え commit
   - 設定の比較（相手の値 / こちらの値）
   - 提案（未導入・乗り換え候補・重複）

   **ページは毎回作り直さず、同じものを更新する。** `artifact.json` に URL があればそれを
   `Artifact` ツールの `url` に渡し、無ければ新規に作って返ってきた URL を書き込む:

   ```json
   { "url": "https://claude.ai/...", "updated": "2026-09-16T11:12:39Z" }
   ```

   日付ごとの節を上に積む形にして、前回までの内容は残す。ページを書く前に `artifact-design`
   skill を読むこと（`Artifact` ツールの決まり）。

9. 提示後、最終確認日を更新するか聞く。承認されたら、リポジトリごとに:

   再 fetch して、レビュー中に upstream が進んでいないか確かめる:

   ```bash
   git -C <path> fetch origin --quiet
   git -C <path> log <default-branch> -1 --pretty='%aI'
   ```

   - 手順4で見た最新 commit と一致すれば、現在時刻（`date -u +"%Y-%m-%dT%H:%M:%SZ"`）を書き込む
   - 進んでいれば**その差分を未レビューとして報告**し、続けてレビューするか、
     手順4で見た最新 commit の日時を書き込んで残りを次回に持ち越すかを聞く

   記録するのは「作業した時刻」ではなく「**実際にレビューし終えた地点**」。現在時刻を無条件に
   書くと、fetch が古い場合やレビューが長引いた場合にその間の commit が永久にスキップされる。

   拒否されたらファイルは触らない。

## 注意

- commit のレビュー（手順4〜6）では、相手は相手の都合で構成を変えているので、ファイル内容の
  差分比較はせず「何を変えたか」だけを見せる。ファイルを読み込むのは手順7だけで、そこでも
  対象は両者が使っているツールに限る
- ツールの提案は積極的にする（手順6）。ただし提案するのは**ツール選定**であって、相手の設定を
  そのまま持ち込むことではない。ユーザーが指定した commit は `git -C <path> show <SHA>` で深掘りする
- 取り込み候補として提示する前に、**その変更がこのリポジトリに該当するか**を確認する。
  相手側の「使わなくなったツールの削除」や「自分が使っているアプリの追加」は、こちらに同じものが
  無ければ無意味（削除対象が存在しない）か、有害（未使用アプリを新規インストールする）になる。
  `rg` で該当箇所を探し、必要ならインストール状況も見る
- 取り込む際は commit をそのまま適用せず、こちらの構成に合わせて読み替える。相手固有の設定
  （好みのモデル、英語表記の癖、本人の語彙、持っていないツールへの参照）は落とし、仕組みだけを移す
- 監視対象の追加・削除は `watchlist.json` を編集する。`note` には「なぜ見るのか」を書く。
  外したリポジトリの clone は消してよい（`$(ghq root)/github.com/<repo>`）
- 一般語と重なるツール名（`delta`, `mise`, `borders` など）を素朴に grep すると誤検出する。
  数える前に `programs.<tool>`、設定ファイル名、upstream の owner 名など具体的な手掛かりに絞り、
  出た数字が妥当か 1 件は中身を見て確かめる
