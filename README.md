# wt

A multi-repo dev workspace built on `git worktree` + `tmux`. One tmux window per branch, shared scripts and env files symlinked everywhere, no Docker.

## Setup

```bash
git clone git@github.com:TheodoreSpeaks/wt.git
cd wt
tmux                       # start a tmux session — wt assumes you're inside one
claude                     # launch Claude inside the tmux pane
```

Then in Claude:

```
/wt-bootstrap
```

That walks you through everything — asks which repos you want to register and whether to apply wt's recommended tmux setup (mouse + window highlighting), then in one pass: copies the config template, writes the tmux block, registers each repo (clone or adopt from local path, infer dev/setup/kill commands from the repo's own files, wire up env-file mappings).

## Principles

1. **One tmux window = one repo on one worktree.** Every active branch lives in its own checkout under `<repo>-wt/<branch>/` and gets a tmux window with the branch name. You never `git checkout` between branches; you switch tmux windows.

2. **Running stuff is one command, no flags.** From inside any worktree (or its canonical), `./run` starts the dev server, `./kill` stops it, `./rm` deletes the worktree. The repo is auto-detected from cwd; you don't pass it.

3. **Symlinks for shared state, not copies.** Env vars, Claude permissions, Claude skills, and the workspace's helper scripts are all symlinks back to a single workspace-level source of truth. Edit once, every worktree picks it up.

4. **Node deps are bun's job, not ours.** We don't symlink `node_modules` (Turbopack hates symlinks crossing project roots anyway). Each worktree runs `bun install` once on creation; bun's global cache deduplicates real disk usage.

5. **No Docker.** Containers are overkill for local dev — slow startup, awkward filesystem semantics, port-mapping yak-shaving. Direct host processes are faster and easier to debug.

6. **Port conflicts are solved by being aggressive, not by isolation.** `./run` always invokes `./kill` for the same repo first. Switching which worktree owns the dev server is a single `./run` away — whatever was on the port dies, the new one takes over.

## A typical session

You sat down to fix an infra cron bug. Walk through it.

**1. Spin up a worktree for the branch.** From the workspace root:

```
./wt infra fix/cron-cleanup
```

This creates `infra-wt/fix-cron-cleanup/` (a git worktree on branch `fix/cron-cleanup`), opens a new tmux window named `fix/cron-cleanup` with two panes, links the env files in, and launches Claude in the left pane. The right pane runs the per-repo `setup:` (e.g. `bun install` for sim) and is yours to use as a regular shell.

**2. Work in the worktree.** Tell Claude what to do, edit files, etc. When you want to start the dev server:

```
./run
```

No args needed — `./run` figures out from your cwd that you're in an `infra` worktree and runs infra's dev command, after killing whatever else was on the same port (so if another worktree was running infra, it dies and yours takes over).

**3. Need to fork off a separate task without losing context here?**

```
/wt-fork rip out the old s3 putobject role, see <url> for the rfc
```

Spawns a parallel Claude in a fresh worktree + tmux window with that prompt. The two work side by side; switch between them with `Ctrl-b w`.

**4. Lost track of what's running where?** From any pane:

```
./status
```

Tree view of every worktree, which tmux window owns it, the last few lines of that window's Claude pane, and PR state (open/merged, review decision, unresolved threads, last comment) — all from one aliased GraphQL call.

**5. Done with the branch?** From inside the worktree:

```
./rm
```

Removes the worktree from disk and kills its tmux window. The branch ref stays in git so you can re-check it out later.

**6. Want to register a repo you didn't bootstrap?** From anywhere:

```
/wt-add-repo git@github.com:foo/bar.git
```

Same inference flow as bootstrap: clone, infer dev/setup/kill/env-mappings, propose, apply.

**7. Edited `wt-config.yaml` or dropped a new script in `shared-scripts/`?**

```
./wt sync
```

Re-symlinks everything into every canonical and worktree so the change propagates.
