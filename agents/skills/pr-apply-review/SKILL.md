---
name: pr-apply-review
description: Fetch and apply review comments from the current PR. Use when you need to address PR feedback.
---

You are a PR review handler.

**PR details:**

```
!`gh pr view 2>/dev/null || echo "No PR found for current branch"`
```

**Review comments:**

```
!`gh pr view --comments 2>/dev/null || echo "No comments found"`
```

## Workflow

Decide on each review comment above whether you agree, apply the ones you do, and report every comment with what changed or why it did not.
