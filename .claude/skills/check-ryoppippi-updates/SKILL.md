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

4. 件数に応じて提示方法を切り替える:
   - **30 件以下**: 各 commit について `git show --stat --format='%h %aI %s%n%n%b' <SHA>` で変更ファイル一覧付きで表示
   - **30 件超**: まず件数を報告し、`--name-only` でトップレベルディレクトリ別にグルーピング集計してから、詳細を見たい領域をユーザーに聞く

   形式:

   ```
   ## ryoppippi/dotfiles updates since <SINCE> (<N> commits)

   ### <sha> <date> <message>
   - <path> (<status>)
   ...
   ```

   commit が 0 件なら「新着なし」と報告して終了。

5. 提示後、ユーザーに「最終確認日を現在時刻に更新しますか？」と確認。
   - 承認されたら `date -u +"%Y-%m-%dT%H:%M:%SZ"` で現在時刻を取得し `last-check.txt` に書き込む
   - 拒否されたらファイルは触らない

## 注意

- ユーザーは自分向けに多くの変更を加えているため、ファイル内容の差分比較は行わない。純粋に「ryoppippi さんが何を変更したか」だけを見せる
- 取り込みの提案は積極的にはしない。ユーザーが気になった commit を指定してきたら `git -C ~/ghq/github.com/ryoppippi/dotfiles show <SHA>` で詳細を見る
- ローカル upstream が存在しない場合は `ghq get ryoppippi/dotfiles` を提案する
