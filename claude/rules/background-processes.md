# Long-Running Processes

A dev server, watcher or anything else that outlives one command is started
with the Bash tool's `run_in_background`, never with `&`, `nohup`, `setsid` or
a `( … & )` subshell. Claude Code tracks a background task and stops it with
the session; a process detached by hand is tracked by nothing, and has been
found holding gigabytes for days after its worktree was gone.

Stop it with `TaskStop` once it has served its purpose, before the final
response. `kill $pid` on a package-manager wrapper (`pnpm exec`, `npx`) stops
the wrapper only, and the server under it carries on.
