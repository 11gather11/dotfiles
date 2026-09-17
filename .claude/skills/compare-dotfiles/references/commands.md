# compare-dotfiles のコマンド集

`<theirs>` は `$(ghq root)/github.com/<repo>`、`<ours>` はこのリポジトリのルート。

## 手順3: 構成の差分

領域ごとのファイル一覧を突き合わせる。パスの prefix が違う場合（`home/claude/skills` と
`agents/skills` など）は、比較する前に相手側の prefix を剥がす:

```bash
diff \
  <(fd -t f . "<theirs>/<their-area>" -E .git | sed "s|^<theirs>/<their-area>/||" | sort) \
  <(fd -t f . "<ours>/<our-area>" -E .git | sed "s|^<ours>/<our-area>/||" | sort)
```

skill は名前だけで足りる:

```bash
fd -t d -d 1 . "<theirs>/<their-skills>" | xargs -n1 basename | sort
fd -t d -d 1 . "<ours>/agents/skills" | xargs -n1 basename | sort
```

同じツールのモジュールがどこにあるかは、名前で探す:

```bash
fd -i '<tool>' "<theirs>" -t f -t d -E .git | head
```

## 手順4: 両方にあるものを比べる

同じ役割のファイルを実際に diff する。**指示文は本文まで読む**。見出しだけの比較は、
どのファイルを本文まで読むかを決めるための下見であって、それで報告を作らない:

```bash
diff -u "<theirs>/<file>" "<ours>/<file>" | rg '^[-+]' | rg -v '^[-+][-+]'
diff -u "<theirs>/<file>" "<ours>/<file>" | rg '^[-+]#{1,4} '   # 下見: どこが動いたか
```

Nix モジュールの設定値は、宣言しているキーを並べて比べる:

```bash
rg -o '^\s+[a-zA-Z_."-]+ =' "<theirs>/<module>" | sed 's/[ =]//g' | sort -u
rg -o '^\s+[a-zA-Z_."-]+ =' "<ours>/<module>"  | sed 's/[ =]//g' | sort -u
```

## 手順5: 意図的な違いの根拠を拾う

こちらのコメントに理由が書いてあるかを確かめる。書いてあれば提案ではなく「意図的」に分類する:

```bash
rg -B6 '<key> = ' "<ours>/<module>"
```
