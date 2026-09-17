# check-dotfiles-updates のコマンド集

`SKILL.md` の各手順から参照する。`<path>` は `$(ghq root)/github.com/<repo>`、`<br>` は
`git -C <path> symbolic-ref refs/remotes/origin/HEAD | sed 's|refs/remotes/||'` の結果、
`<SINCE>` は `last-check.json` の値（無ければ 30 日前）。

## 手順2: clone を用意する

無ければ blobless clone（履歴のメタデータは全部持ちつつ、過去版のファイル実体は取らない。
現在のファイルは checkout されるので grep できる）:

```bash
git clone --filter=blob:none "https://github.com/<repo>" "$(ghq root)/github.com/<repo>"
```

あれば更新する:

```bash
git -C <path> fetch origin --quiet
```

## 手順4: 新着 commit を数える

```bash
git -C <path> log <br> --since="<SINCE>" --no-merges \
  --pretty=format:'%h%x09%aI%x09%an%x09%s' \
  | rg -v '\[bot\]|renovate|dependabot' \
  | rg -v 'update flake input|update llm-agents|chore\(deps\)|: [0-9.]+ -> [0-9.]+'
```

## 手順6: 指示文と skill の変更

パスで絞る。件数に埋もれて見落とすため、全リポジトリ分をこれで出す:

```bash
git -C <path> log <br> --since="<SINCE>" --no-merges \
  --pretty=format:'%h%x09%aI%x09%s' \
  -- '**/CLAUDE.md' '**/AGENTS.md' '**/GEMINI.md' '**/.cursor/**' \
     '**/skills/**' '**/rules/**' '**/shared/**' '**/prompts/**' \
  | rg -v '\[bot\]'
```

skill の増減は名前で分かるので、範囲の差分から取る:

```bash
git -C <path> diff --name-status <前回の地点>..<br> -- '**/skills/**/SKILL.md'
```

指示文で何が変わったかは、その commit の追加・削除行の見出しから:

```bash
git -C <path> show <sha> -- <file> | rg '^[-+]#{1,4} |^[-+]- '
```

## 手順7: 乗り換えと採用の広がり

乗り換えの commit:

```bash
git -C <path> log <br> --since="<SINCE>" --no-merges \
  --pretty=format:'%h%x09%s' \
  --grep='replace' --grep='instead of' --grep='in favou\?r of' \
  --grep='migrate' --grep='switch to' --grep='drop' -i
```

こちらに無いツールの採用数:

```bash
for p in <各 clone>; do rg -l --no-messages '<tool>' "$p" -g '!.git' >/dev/null && echo "$p"; done
```

## 手順8: 同じツールを持つ相手を探す

```bash
for p in <各 clone>; do fd -i '<tool>' "$p" -t f -t d -E .git | head -1 | rg -q . && echo "$p"; done
```

## 手順10: レビューし終えた地点を確かめる

```bash
git -C <path> fetch origin --quiet
git -C <path> log <br> -1 --pretty='%aI'
```
