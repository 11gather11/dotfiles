---
name: toolbelt
description: Rebuild and republish the dotfiles reference page — what is installed here and how to use it. Use when tools are added or removed, when the page has gone stale, or when the user asks to update the toolbelt.
---

# Toolbelt page

この環境に何が入っていて、どう使うのかをまとめた 1 枚のページを作り直す。

- 公開先: <https://claude.ai/code/artifact/e12e959b-8f13-4965-a0d3-53ef5e21403e>
- 中身: `content.json`（説明文）
- 骨組み: `template.html`（CSS・JS・プレースホルダ）
- 生成: `generate.nu`

## なぜ分けてあるか

ページには 2 種類の情報が混ざっている。

- **何が入っているか** — `packages.nix` などから機械的に読める。ツールを足し引きすると変わる
- **それが何なのか** — 人が書いた説明。一度書けば変わらない

`content.json` が後者を保持し、`generate.nu` が前者と突き合わせて**説明の抜け**を報告する。
設定にあるのに `content.json` に無いものが「未記載」として出るので、書き足す対象が分かる。

## 手順

1. まず差分だけ見る:

   ```bash
   cd .claude/skills/toolbelt
   nix shell nixpkgs#nushell --command nu generate.nu --check
   ```

   `installed:` に実際の数、`drift:` に未記載のものが出る。

2. 未記載があれば `content.json` に追記する。構造は次のとおり:

   ```
   tabs[] → { id, label, lede, sections[] }
     sections[] → { title, src?, note?, items[] }
       items[] → { name, desc, expand?, tag? }
   ```

   - `desc` には HTML を書いてよい（`<b>` や `<code>` を使っている）
   - `tag.kind` は `t-new`（新規・自前）／`t-warn` `t-un`（未活用・要設定）／`t-cfg` `t-gui`（補足）
   - 消えたツールは該当 item を削除する

3. **先にコミットしてから** HTML を生成する:

   ```bash
   nix shell nixpkgs#nushell --command nu generate.nu
   ```

   `toolbelt.html` が同じディレクトリに出る。フッターに生成日時と、その内容が
   どのコミット時点かが入る。未コミットの変更が残っていると「＋未コミットの変更」と
   出る — 正確ではあるが、公開するページにはコミット済みの状態を載せたい。

4. **同じ URL に再公開する。** Artifact ツールに `url` を渡すこと。渡さないと別ページが増える:

   ```
   Artifact(file_path: ".claude/skills/toolbelt/toolbelt.html",
            url: "https://claude.ai/code/artifact/e12e959b-8f13-4965-a0d3-53ef5e21403e",
            favicon: "🧰")
   ```

## 注意

- `toolbelt.html` は生成物。**直接編集しない**。直すのは `content.json` か `template.html`
- 数え方はページ下部のフッターにも書いてある。ツールが増減したらそこも `content.json` 側で直す
- タブを増やすなら `content.json` の `tabs` に足すだけでよい。`template.html` と `generate.nu` は
  タブ数に依存していない
- 配色は fish のテーマ（kanagawa）から取っている。テーマを変えるなら `template.html` の
  `:root` にある変数を差し替える。ライト・ダーク両方の定義があるので両方直すこと
