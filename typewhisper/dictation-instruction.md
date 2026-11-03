<!--
Canonical dictation instruction (LLM prompt) for TypeWhisper.

TypeWhisper has no HTTP API for creating workflows, so this cannot be synced
like dictionary.json. It is kept here as the source of truth: paste the body
below into the "指示" field of a custom workflow whose trigger is "常に"
(Settings > Workflows), and leave its "微調整" fields empty so the rules are not
duplicated.

Recommended provider: the OpenAI / ChatGPT plugin with the existing Codex login
imported, using a light model, set as the global LLM fallback. The transcription
engine is Qwen3 ASR, which TypeWhisper does not pass dictionary terms to, so this
prompt is what turns misheard words such as 炎 back into Hono. Apple
Intelligence or a local MLX model keeps everything on-device instead, but with
less context to tell technical terms from ordinary words.

Note that any workflow adds latency after the transcription completes. Rules
that are purely literal substitutions belong in dictionary.json instead, which
applies instantly; keep this prompt for the context-dependent rules that a
blunt find-and-replace would get wrong.
-->

Keep the language of the dictation. For Japanese dictation, do not translate it into English.

# Japanese Voice Input Instructions

## Line Break Handling

When the input includes the word "改行", insert a real line break (not a literal "\n", but an actual new line) at that point in the output. If similar-sounding words like "開業" are misrecognized but clearly intended to mean a line break based on context, treat them as "改行" and insert a line break accordingly.

A line that ends at a dictated line break is a list item or a heading, not the middle of a sentence, so drop a trailing "、" or "。" left before the break.

## Number Formatting

Write large Japanese amounts with 万 and 億 rather than spelling out every digit: `250万円`, not `2,500,000円`; `1億2000万円`, not `120,000,000円`. Keep small numbers, dates and times as Arabic numerals (`11月4日`, `午後3時半`, `30分`).

## Sentence Spacing Rule

After generating the text, remove all unnecessary half-width spaces, including those at the beginning, between, and at the end of sentences.

## Special Term Conversion

When the input contains terms that are difficult to transcribe correctly (e.g. uncommon Kanji names, Katakana loanwords, or proper nouns), convert them into their most natural and widely accepted written forms. For Katakana words that correspond to English technical terms, use their standard English spellings.

Only apply this when the context is clearly about software development — these katakana words also have ordinary Japanese meanings, and rewriting those would be wrong.

### Examples:

- `カーソル` → `Cursor` (the editor; leave it as カーソル when it means a text cursor)
- `バン` → `Bun` (the runtime; leave it alone in ordinary words such as バンド or カバン)
- `ニックス` → `nix`
- `フィッシュ` → `fish` (the shell)
- `ヴィテスト` / `ビーテスト` / `ブイテスト` → `Vitest`
- `ホノ` / `ほの` / `炎` → `Hono` (the web framework; the recogniser hears it as the word 炎, so rewrite 炎 only when it sits among code, frameworks or libraries, and leave it alone in ordinary prose)

日本語の中に出てくる開発用の英単語（特に git のサブコマンドなど）は、英単語のまま残して。

## Bracket Insertion

For brackets, insert them based on voice commands and context:

- When "かっこ" is detected → insert "（" or "）"
- When "かぎかっこ" is detected → insert "「" or "」"

The choice between opening or closing brackets should be determined automatically based on the context and sentence structure.

### Examples:

```
Input: "注意事項かっこ以下の点に気をつけてくださいかっことじ"
Output: "注意事項（以下の点に気をつけてください）"

Input: "かぎかっこ引用開始かっことじと言いました"
Output: "「引用開始」と言いました"

Input: "昨日の会議でかぎかっこ承知いたしましたかぎかっことじという返事をもらいました"
Output: "昨日の会議で「承知いたしました」という返事をもらいました"
```
