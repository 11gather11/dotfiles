---
name: check-ryoppippi-updates
description: Show new commits on ryoppippi/dotfiles main since the last check date stored in last-check.txt. Use when the user asks to check ryoppippi's updates, sync from upstream reference, or see what changed on ryoppippi's dotfiles.
---

# Check ryoppippi/dotfiles updates

このリポジトリは `ryoppippi/dotfiles` を参考にしている。最終確認日以降の upstream commit を提示する。

upstream はローカルに ghq で clone 済み: `~/ghq/github.com/ryoppippi/dotfiles`

## 手順

1. 状態ファイル `.claude/skills/check-ryoppippi-updates/last-check.txt` を読む
   - 存在しない場合は「初回実行です。開始日を指定してください（ISO 8601 例: `2026-01-01T00:00:00Z`）、または最初から全部見たい場合は `all` と入力してください」とユーザーに聞く
   - 中身は ISO 8601 形式の日時 1 行のみ

2. ローカルの upstream を最新化:

   ```bash
   git -C ~/ghq/github.com/ryoppippi/dotfiles fetch origin main
   ```

3. 指定日時以降の commit を取得（`all` 指定時は `--since` を省略）:

   ```bash
   git -C ~/ghq/github.com/ryoppippi/dotfiles log origin/main \
     --since="<SINCE>" \
     --pretty=format:'%h%x09%aI%x09%s' \
     --no-merges
   ```

   upstream は依存更新 bot の commit が大半を占める（数か月分で 7 割以上になる）。
   実質的な変更だけを見るため、まず自動更新を除外した一覧を作る:

   ```bash
   git -C ~/ghq/github.com/ryoppippi/dotfiles log origin/main \
     --since="<SINCE>" --pretty=format:'%h%x09%aI%x09%s' --no-merges \
     | rg -v 'chore\(nix\): update flake input|chore\(nix\): update llm-agents|chore\(deps\)'
   ```

   全体件数と、除外後の件数の両方を報告する。

4. 件数に応じて提示方法を切り替える（件数は**除外後**で判断する）:
   - **30 件以下**: 各 commit について `git show --stat --format='%h %aI %s%n%n%b' <SHA>` で変更ファイル一覧付きで表示
   - **30 件超**: まず件数を報告し、領域別（darwin / nvim / skills / shell / nix 基盤 など）に分類した表を出してから、詳細を見たい領域をユーザーに聞く

   形式:

   ```
   ## ryoppippi/dotfiles updates since <SINCE> (<N> commits)

   ### <sha> <date> <message>
   - <path> (<status>)
   ...
   ```

   commit が 0 件なら「新着なし」と報告して終了。

5. 提示後、ユーザーに「最終確認日を更新しますか？」と確認。承認されたら:

   まず再 fetch し、レビュー中に upstream が進んでいないか確かめる:

   ```bash
   git -C ~/ghq/github.com/ryoppippi/dotfiles fetch origin main
   git -C ~/ghq/github.com/ryoppippi/dotfiles log origin/main -1 --pretty='%aI'
   ```

   - 手順3で取得した最新 commit と一致すれば、`date -u +"%Y-%m-%dT%H:%M:%SZ"` を書き込む
   - 進んでいれば**その差分を未レビューとして報告**し、続けてレビューするか、
     手順3で見た最新 commit の日時（`%aI`）を書き込んで残りを次回に持ち越すかを聞く

   記録するのは「作業した時刻」ではなく「**実際にレビューし終えた地点**」。現在時刻を
   無条件に書くと、fetch が古い場合やレビューが長引いた場合にその間の commit が
   永久にスキップされる。

   拒否されたらファイルは触らない。

## 注意

- ユーザーは自分向けに多くの変更を加えているため、ファイル内容の差分比較は行わない。純粋に「ryoppippi さんが何を変更したか」だけを見せる
- 取り込みの提案は積極的にはしない。ユーザーが気になった commit を指定してきたら `git -C ~/ghq/github.com/ryoppippi/dotfiles show <SHA>` で詳細を見る
- 取り込み候補として提示する前に、**その変更がこのリポジトリに該当するか**を確認する。
  upstream 側の「使わなくなったツールの削除」や「自分が使っているアプリの追加」は、
  こちらに同じものが無ければ無意味（削除対象が存在しない）か、有害（未使用アプリを
  新規インストールする）になる。`rg` で該当箇所を探し、必要ならインストール状況も見る
- 取り込む際は upstream の commit をそのまま適用せず、こちらの構成に合わせて読み替える。
  相手固有の設定（好みのモデル、UK English、本人の語彙、持っていないツールへの参照）は
  落とし、仕組みだけを移す
- ローカル upstream が存在しない場合は `ghq get ryoppippi/dotfiles` を提案する
