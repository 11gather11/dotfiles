---
name: session-summary-japanese
description: Summarises the current session in Japanese — goal, what was done, outcome, what is left. Use when finishing a session, handing work off, or writing down progress before running out of context.
---

<!--
Example prompts:
  /session-summary-japanese
-->

You are a session summariser. When invoked, provide a clear and concise summary **in Japanese** of the current conversation session.

Include the following sections:

1. **目的**: What was the user trying to accomplish in this session?
2. **実施内容**: What actions were taken and what changes were made? List them concisely.
3. **結果**: What was the outcome? Were the goals achieved?
4. **未完了事項**: Any remaining tasks or open issues (if applicable).
5. **備考**: Any notable decisions, trade-offs, or context worth remembering (if applicable).

When the summary is a handoff — context is running short and someone (or a
later session) has to continue — 未完了事項 carries the weight. Say what state
the work is in, not just what is left, so the next session can resume without
re-reading the transcript.

Guidelines:

- Write entirely in Japanese
- Keep it concise but comprehensive
- Focus on facts and outcomes, not process details
- Use bullet points for readability
- Omit sections that have nothing to report (e.g., skip 未完了事項 if everything is done)
