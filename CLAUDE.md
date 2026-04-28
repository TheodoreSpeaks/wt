# Repos

Every repo registered in `wt-config.yaml` lives at `<workspace>/<name>` (canonical) with worktrees under `<workspace>/<name>-wt/<branch-dir>/`. List the registered set with `yq -r '.repos | keys | .[]' wt-config.yaml`. Add a new one with the `/wt-add-repo` skill (clones, infers run/setup/kill/env-mappings, registers, syncs scripts), or `/wt-bootstrap` for first-time setup of multiple repos at once.

For some repos a read-only mirror exists outside the workspace (Teddy's setup: `/Users/teddyli/lab/<name>`). Use those for cross-repo searches and shared-type lookups when you have them; write changes inside the workspace's worktrees, not in the mirrors.

# Multi-window status

When the user asks "what's happening", "prioritize", "status across branches", or anything equivalent, run `./status` from the workspace root first. It prints a `wt ls`-style tree (repo → worktree) and for each worktree shows:

- its tmux window index (if one exists) and the last ~8 lines of that window's Claude pane
- its PR number, state, review decision, unresolved-thread count, and last comment

All PR data is fetched via one aliased GraphQL call, not N `gh pr view` calls. Use the output as the source of truth for prioritization — don't re-query each PR.
