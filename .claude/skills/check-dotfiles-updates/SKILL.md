---
name: check-dotfiles-updates
description: Show new commits on the watched dotfiles repositories since each one was last checked. Use when the user asks to check upstream dotfiles, catch up on what others changed, or look for new tools worth adopting.
---

# Check watched dotfiles updates

このリポジトリは自分用に育てていく前提で、他人の dotfiles は**最新の動向を知るための情報源**として監視する。取り込みは前提ではない。

- 監視対象: `watchlist.json`（このディレクトリ、git 管理）
- 最終確認日: `last-check.json`（このディレクトリ、git 管理外）。リポジトリごとに ISO 8601 で保持

## 手順

1. `watchlist.json` と `last-check.json` を読む。

   引数でリポジトリ名（`Mic92/dotfiles` など）が渡された場合はそれだけを対象にする。
   渡されなければ watchlist 全件。

2. 各リポジトリのローカル clone を用意する。パスは `$(ghq root)/github.com/<repo>`。

   無ければ blobless clone で取得する（履歴だけ要るのでファイル実体は不要、その分軽い）:

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

6. 提示後、最終確認日を更新するか聞く。承認されたら、リポジトリごとに:

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

- 相手は相手の都合で構成を変えている。ファイル内容の差分比較はせず、「何を変えたか」だけを見せる
- 取り込みの提案は積極的にはしない。ユーザーが指定した commit を `git -C <path> show <SHA>` で深掘りする
- 取り込み候補として提示する前に、**その変更がこのリポジトリに該当するか**を確認する。
  相手側の「使わなくなったツールの削除」や「自分が使っているアプリの追加」は、こちらに同じものが
  無ければ無意味（削除対象が存在しない）か、有害（未使用アプリを新規インストールする）になる。
  `rg` で該当箇所を探し、必要ならインストール状況も見る
- 取り込む際は commit をそのまま適用せず、こちらの構成に合わせて読み替える。相手固有の設定
  （好みのモデル、英語表記の癖、本人の語彙、持っていないツールへの参照）は落とし、仕組みだけを移す
- 監視対象の追加・削除は `watchlist.json` を編集する。`note` には「なぜ見るのか」を書く
- GitHub のコード検索（`gh search code`）は結果が不安定で、レート制限にもかかりやすい。
  「このリポジトリは X を使っているか」を確かめるなら、clone して `rg` する方が確実
