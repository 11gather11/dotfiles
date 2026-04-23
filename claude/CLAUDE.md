# User Memory

Personal preferences that apply to all projects.

## About Me

- My name is 11gather11
- Always communicate in Japanese
- All code-related output (commits, comments, docs, PRs) must be in English

## Code Comments Policy

### Forbidden

- Do NOT add comments explaining what was changed or why a change was made
- Comments like `// changed from X to Y` or `// updated for feature Z` are forbidden
- If a change needs explanation, write it in the git commit message instead
- Git commits should contain detailed explanations of what changed and why
- Do NOT remove existing comments that explain logic, behaviour, or intent — even if they seem obvious to you. Only remove comments that are clearly outdated or factually wrong.

### Required

- **JSDoc**: Always write JSDoc comments for exported functions, classes, types, and interfaces. Include `@param`, `@returns`, and `@example` where appropriate.
- **Complex logic**: When a function or block contains non-trivial logic (algorithms, bitwise operations, state machines, multi-step transformations, etc.), add line-by-line comments explaining what each step does and why. The reader should be able to follow the logic without having to reverse-engineer it.
- Only skip comments for code that is truly self-explanatory (simple getters, one-liner utilities, etc.).
