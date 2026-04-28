---
name: wt-add-repo
description: Bootstrap a new repo into the workspace — clone (from a git URL or an existing local clone), infer its dev/setup/kill commands and env-file mappings from the repo's own files, register it in wt-config.yaml, and sync shared-scripts so `./wt <name> <branch>` immediately works. Use when the user says "/wt-add-repo", "/add-repo" (legacy alias), "add a repo", "add-dir", "register this repo", "set up <repo>", or pastes a git URL or local path with intent to integrate.
---

# wt-add-repo — bootstrap a repo into the workspace so `./wt <name> <branch>` just works

The workspace expects every registered repo to live at `<workspace>/<name>` and have an entry under `repos:` in `wt-config.yaml`. Worktrees go under `<name>-wt/<branch-dir>/`. Three shared scripts (`run`, `kill`, `rm`) get symlinked into every canonical and worktree by `wt sync`.

This skill does the full bootstrap. **Lean on file inference, not user prompting** — read `package.json`, `Cargo.toml`, `go.mod`, lockfiles, `.env.example`, etc. and propose a complete config. Only ask the user about things you genuinely cannot determine from disk.

## Inputs

- Required, one of:
  - A git URL (`git@github.com:owner/repo.git`, `https://github.com/owner/repo`).
  - A local path to an existing clone (e.g. `/Users/teddyli/lab/foo`). The original repo at that path is left untouched.
- Optional: a short name. Default to the repo basename. `<workspace>/<name>` must not collide with an existing dir or yaml entry.

## Environment

This skill is workspace-local. Resolve the workspace root from this skill's base directory (passed as "Base directory for this skill" when the skill is invoked) — it's three levels up from `<base>/SKILL.md`:

```bash
WORKSPACE="$(cd "<base-dir>/../../.." && pwd)"
```

Every absolute path below is relative to `$WORKSPACE`.

## Flow

### 1. Clone or adopt

There are three input shapes — handle each:

**(a) Git URL** — fresh clone:
```bash
git clone "$URL" "$WORKSPACE/$NAME"
```

**(b) Local path to an existing clone, anywhere on disk** — clone-with-local. This hardlinks `.git/objects` (cheap, doesn't duplicate history), skips `node_modules` / build artifacts entirely, and leaves the source repo untouched. Then rewrite `origin` to the source's actual remote so `git fetch`/`push` go to the real github (not back to the local copy):
```bash
SRC_REMOTE=$(git -C "$SRC_PATH" remote get-url origin 2>/dev/null || true)
git clone --local "$SRC_PATH" "$WORKSPACE/$NAME"
if [ -n "$SRC_REMOTE" ]; then
  git -C "$WORKSPACE/$NAME" remote set-url origin "$SRC_REMOTE"
fi
```

**(c) Already at `<workspace>/<name>` with a valid `.git`** — adopt in place, no clone.

If `<name>` is already a key under `repos:` in `wt-config.yaml`, ask the user: overwrite, rename, or abort.

### 2. Infer everything possible from the repo

Walk the freshly cloned tree and propose values for each field below. Read multiple files when needed; don't ask the user about anything you can determine.

**`dir`** — relative to workspace root, where the runnable app lives.
- Default: `<name>` (repo root).
- If the repo has `cmd/<bin>/main.go` (Go), use `<name>/<that>` only if `go run ./cmd/<bin>` won't work from the repo root. Usually keep `dir` at repo root and put the path in the `run` command.
- If the repo is a monorepo with multiple runnable apps, list candidates and ask the user.

**`run`** — bash, executed from `dir`. Detect package manager and entry script.
- `bun.lock` → `bun run dev` / `bun run start` (whichever exists in `package.json`'s `scripts`).
- `pnpm-lock.yaml` → `pnpm dev` / `pnpm start`.
- `package-lock.json` → `npm run dev` / `npm start`.
- `yarn.lock` → `yarn dev` / `yarn start`.
- `Cargo.toml` → `cargo run` (or `cargo run --bin <name>` if multiple bins).
- `go.mod` + `cmd/<bin>/main.go` → `go run ./cmd/<bin>`.
- `Makefile` with a `dev:` / `run:` / `serve:` target → `make <target>`.
- If multiple plausible commands exist, present candidates and ask.

**`setup`** — bash, run in the worktree's right pane on every `./wt <name> <branch>`.
- `bun.lock` → `bun install`.
- `pnpm-lock.yaml` → `pnpm install`.
- `package-lock.json` → `npm install`.
- `yarn.lock` → `yarn install`.
- `Cargo.lock` → `cargo build`.
- `go.mod` → `go mod download`.
- Skip if no recognizable lockfile / manifest.

**`ports`** — for the kill block.
- Grep `.env.example` / `.env.template` for `^PORT=` and `^[A-Z_]*_PORT=`.
- Grep source for `\.listen\(\d+`, `:\d{4,5}\b`, `Addr:.*":\d+"`, etc.
- If nothing found, ask the user. If multiple, present them and let the user prune.

**Env-file mappings** — list every `.env.example`, `.env.template`, `.env.local.example`, `.env.development.example` (etc.) in the repo. For each, propose:

```yaml
- repo: <name>
  source: env/.env-<name>[-<scope>]      # workspace-managed file (placeholder created)
  dest: <relative path inside repo>      # e.g. apps/web/.env, packages/db/.env
```

If the repo nests multiple packages each with their own env file, propose one mapping per package. Use `<scope>` segments in the source filename to disambiguate (e.g. `env/.env-foo-app`, `env/.env-foo-db`).

### 3. Propose the inferred config to the user

Print the complete proposal as a single block — yaml snippet plus the env placeholder paths to be created. Example shape:

```
Proposed config for <name>:

  repos.<name>:
    dir: <name>
    run: bun run dev
    setup: bun install
    kill: |
      for p in 3000; do
        pids=$(lsof -ti :$p 2>/dev/null)
        if [ -n "$pids" ]; then
          echo "killing :$p ($pids)"
          kill -9 $pids
        else
          echo "nothing on :$p"
        fi
      done

  mappings additions:
    - repo: <name>
      source: env/.env-<name>
      dest: .env

  Env placeholder files to create (you'll need to fill in real values):
    $WORKSPACE/env/.env-<name>
```

Then ask: "Apply this, or want to tweak anything?" Use AskUserQuestion only for the genuine ambiguities surfaced earlier (multiple run commands, multiple ports, multiple app dirs); otherwise a free-form yes/edit/no is fine.

### 4. Apply (after approval)

1. **Edit `wt-config.yaml` with the Edit tool** (NOT `yq -i` — block-scalar formatting must be preserved).
   - Insert the new `repos.<name>` block above the `mappings:` line.
   - Append the proposed mapping entries inside the existing `mappings:` list.
2. **Create env placeholder files** so the user knows where to populate values:
   ```bash
   for f in <env paths>; do
     [ -e "$f" ] || touch "$f"
   done
   ```
3. **Sync shared scripts** so `./run`, `./kill`, `./rm` symlinks land in the new canonical:
   ```bash
   $WORKSPACE/wt sync
   ```

### 5. Verify and report

```bash
yq -r '.repos.<name>' $WORKSPACE/wt-config.yaml
ls -la $WORKSPACE/<name>/{run,kill,rm}
```

Report to the user:
- Confirmation that yaml parses + symlinks are in place.
- The exact list of env placeholder files they need to fill in (with the absolute paths).
- The next command: `./wt <name> <branch>` to create a worktree, or `cd <workspace>/<name> && ./run` to start dev from the canonical.

Don't auto-spawn worktrees, don't auto-start the dev server.

## Gotchas

- **Block-scalar formatting**: `yq -i` reflows yaml and mangles the `kill: |` block. Always Edit.
- **Env mappings + secrets**: never copy values from the repo's `.env.example` into the placeholder. Just create the file empty so the user knows the path.
- **Don't pepper the user with questions**: anything readable from `package.json` / `Cargo.toml` / `go.mod` / `.env.example` should be inferred, not asked.
