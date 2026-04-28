---
name: wt-fork
description: Spawn a parallel Claude session in a new git worktree via the workspace `wt` script, then paste a prompt into it via tmux. Use ONLY when the user explicitly asks to fork / spawn / delegate a task to another Claude (e.g. "fork this", "spawn a claude", "/wt-fork", "/wt-fork" legacy alias). NEVER invoke proactively — this creates real files and a billable Claude session.
---

# wt-fork — Spawn a parallel Claude in a new worktree

Delegate an isolated, well-scoped task to a fresh Claude instance running in a separate tmux window. Useful for big refactors, audits, or bugfixes that would otherwise consume a lot of the current session's context.

## Hard constraints

- **Only run this skill when the user explicitly asks for it.** Never proactively.
- **Do not skip the 5-second wait.** The Claude CLI needs time to boot before it can accept input.
- **Use `tmux load-buffer` + `tmux paste-buffer` for the prompt**, not raw `tmux send-keys` with a multi-line string. Send-keys collapses formatting and may submit prematurely on embedded newlines.

## Environment

This skill is workspace-local — it lives at `<workspace>/.claude/skills/wt-fork/`. Resolve the workspace root from this skill's base directory (passed as "Base directory for this skill" when the skill is invoked):

```bash
WORKSPACE="$(cd "<base-dir>/../../.." && pwd)"
```

Equivalent shortcut if the user invoked `/wt-fork` from inside the workspace tree (cwd is the workspace root or any descendant):

```bash
WORKSPACE=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null \
  | sed -E 's|/(sim|copilot|infra|[^/]+)(-wt/[^/]+)?$||')
```

— or just hardcode it from `pwd` if you can see the workspace path in the cwd. Either way, every absolute path below is relative to `$WORKSPACE`.

The `wt` script lives at `$WORKSPACE/wt`:

```
$WORKSPACE/wt <repo> <branch>
```

`<repo>` is any name listed under `repos:` in `wt-config.yaml` — list them with:

```
yq -r '.repos | keys | .[]' "$WORKSPACE/wt-config.yaml"
```

The script:

1. Creates a git worktree at `<repo>-wt/<sanitized-branch>/` (where `/` in the branch name becomes `-` in the directory name, but the tmux window keeps the original branch name).
2. Symlinks shared env files from `env/` into the worktree per `wt-config.yaml`'s `mappings:`.
3. Symlinks `shared-scripts/*` (`run`, `kill`, `rm`) into the worktree.
4. Opens a new tmux window named `<branch>`, split horizontally.
5. In the right pane, runs the per-repo `setup:` command from `wt-config.yaml` if defined (e.g. `bun install`, `cargo build`).
6. Launches `claude` in the left pane (pane 0).

## Flow

### 1. Plan the fork

- Pick a branch name (kebab-case, conventional prefix like `fix/`, `feat/`, `chore/`).
- Draft the prompt. Write it as if briefing a colleague with zero context from the current conversation:
  - Include file paths with line numbers (`apps/sim/lib/foo.ts:42-60`).
  - State goals concretely, including any metrics or context from prior analysis.
  - List project conventions explicitly (e.g. for sim: bun/bunx not npm/npx, absolute imports `@/...`, fail-fast no-backup-code, no non-TSDoc comments, `withRouteHandler` on API routes, `createLogger` from `@sim/logger`). Conventions vary per repo — check the canonical's `CLAUDE.md` / `AGENTS.md` if unsure.
  - Add explicit "do NOT" boundaries: don't commit, don't open a PR, don't modify unrelated files, etc.
  - End with: "When done, run type checks and relevant tests, summarize the diff, and stop."
- Proceed directly to step 2 — no approval gate. The user invoked `/wt-fork` with a task description; that is the authorization.

### 2. Write the prompt to a temp file

Preserves multi-line formatting when pasting:

```
# Use Write tool
/tmp/prompt-<branch-sanitized>.md
```

### 3. Create the worktree (spawns Claude)

```bash
cd "$WORKSPACE" && ./wt <repo> <branch>
```

Tail the output — it prints the worktree path and confirms "Opening in tmux…".

Verify the window exists:

```bash
tmux list-windows -F "#{window_name}" | grep -F "<branch>"
```

### 4. Wait 5 seconds for Claude to boot

The leading-sleep guard blocks synchronous `sleep 5 && ...` commands. Use a background sleep instead (runs asynchronously and notifies on completion):

```
# Bash tool with run_in_background: true
sleep 5 && echo ready
```

Wait for the task-completion notification before proceeding to step 5. Do not poll.

### 5. Paste the prompt and submit

```bash
tmux load-buffer /tmp/prompt-<branch-sanitized>.md
tmux paste-buffer -t "<branch>.0"
sleep 1 && tmux send-keys -t "<branch>.0" Enter
```

The `sleep 1` between paste and Enter gives the Claude CLI time to register the paste before submission.

### 6. Verify the prompt landed

```bash
tmux capture-pane -t "<branch>.0" -p -S -40 | tail -40
```

You should see the end of the prompt followed by a thinking indicator (e.g. "Determining…", "Undulating…"). If you see the prompt but no thinking indicator, Enter may not have fired — re-send just the Enter:

```bash
tmux send-keys -t "<branch>.0" Enter
```

## Checking in on a forked Claude

```bash
tmux capture-pane -t "<branch>.0" -p -S -80 | tail -80
```

Or switch to the window visually with `Ctrl-b w` (tmux prefix + w) and pick from the list.

## Cleanup

When the forked work is merged or abandoned, remove the worktree:

```bash
cd "$WORKSPACE" && ./wt <repo> <branch> --rm
```

This deletes the git worktree and kills the tmux window. The branch itself stays in git (local or remote) — remove it separately if unwanted.

## Parallelism

You can fork multiple Claudes. Each gets its own worktree, tmux window, and branch. Typical pattern: two independent fixes that shouldn't share a branch — fork each with its own scoped prompt, review both diffs separately.
