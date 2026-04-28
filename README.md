# wt

A multi-repo dev workspace built on `git worktree` + `tmux`. One tmux window per branch, shared scripts and env files symlinked everywhere, no Docker.

## Setup

```bash
git clone <wt-repo-url> wt
cd wt
claude
```

Then in Claude:

```
/wt-bootstrap
```

That walks you through everything — copies the config template, sets up tmux mouse + window highlighting, and registers each repo you want (clone or adopt from local path, infer dev/setup/kill commands from the repo's own files, wire up env-file mappings).

## Principles

1. **One tmux window = one repo on one worktree.** Every active branch lives in its own checkout under `<repo>-wt/<branch>/` and gets a tmux window with the branch name. You never `git checkout` between branches; you switch tmux windows.

2. **Running stuff is one command, no flags.** From inside any worktree (or its canonical), `./run` starts the dev server, `./kill` stops it, `./rm` deletes the worktree. The repo is auto-detected from cwd; you don't pass it.

3. **Symlinks for shared state, not copies.** Env vars, Claude permissions, Claude skills, and the workspace's helper scripts are all symlinks back to a single workspace-level source of truth. Edit once, every worktree picks it up.

4. **Node deps are bun's job, not ours.** We don't symlink `node_modules` (Turbopack hates symlinks crossing project roots anyway). Each worktree runs `bun install` once on creation; bun's global cache deduplicates real disk usage.

5. **No Docker.** Containers are overkill for local dev — slow startup, awkward filesystem semantics, port-mapping yak-shaving. Direct host processes are faster and easier to debug.

6. **Port conflicts are solved by being aggressive, not by isolation.** `./run` always invokes `./kill` for the same repo first. Switching which worktree owns the dev server is a single `./run` away — whatever was on the port dies, the new one takes over.

## Day-to-day

From inside any worktree (or canonical):

- `./run` — start dev server (auto-detects repo from cwd, kills the prior one first)
- `./kill` — stop dev server
- `./rm` — remove this worktree (kills tmux window + git worktree remove)

From the workspace root:

- `./wt <repo> <branch>` — create a worktree + tmux window for a branch
- `./wt sync` — re-sync shared-scripts and env mappings into every canonical + worktree
- `./status` — tree view of every worktree, its tmux window, and its PR state
- `/wt-add-repo` — register another repo
- `/wt-fork` — spawn a parallel Claude in a new worktree for an isolated task
