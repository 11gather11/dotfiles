# Claude in Chrome Tabs

Every session gets its own tab group, and Chrome keeps it after the session ends.

- Before the final response, close every tab in your group with `tabs_close_mcp`, including blank tabs and ones left by a failed attempt. Closing the last tab removes the group.
- Find your tabs with `tabs_context_mcp` and `createIfEmpty: false`. With `true` it opens a new window and group, so pass it only when you are about to use the browser.
- Never close the user's tabs or another session's group.
- Leave a tab open only when the user needs to keep looking at it, and say which one and why. If the browser is unreachable, say the cleanup could not be done.
