---
name: wt-bootstrap
description: First-time setup wizard for a freshly-cloned wt workspace — collects all decisions up front (which repos, tmux mouse override, yaml conflict), then runs every setup step in one pass with no further questions. Use when the user says "/wt-bootstrap", "bootstrap this workspace", "set up wt", or runs into a "wt-config.yaml not found" error from `./wt`.
---

# wt-bootstrap — first-time setup wizard

Walks a freshly-cloned `wt` workspace through to a working state in three phases:

1. **Collect** every decision up front in one combined prompt.
2. **Execute** all the work in one pass — no more questions.
3. **Report** what landed, including any inference picks the user should review.

## Environment

Resolve the workspace root from this skill's base directory (passed as "Base directory for this skill"):

```bash
WORKSPACE="$(cd "<base-dir>/../../.." && pwd)"
```

## Phase 0 — sanity check

Before asking anything, confirm we're actually in a wt workspace:

```bash
test -f "$WORKSPACE/wt-config.example.yaml" || { echo "no wt-config.example.yaml — is this actually a wt workspace?"; exit 1; }
test -f "$WORKSPACE/wt"                     || { echo "no wt script — is this actually a wt workspace?"; exit 1; }
```

If either is missing, surface and stop — likely the wrong dir or a corrupt clone.

## Phase 1 — collect ALL decisions up front

Inspect state and gather everything we'll need to ask the user **before** doing any work. Combine into a **single** AskUserQuestion (or a single free-form prompt). Don't pepper.

State to inspect first:

```bash
yaml_exists=false
yaml_has_repos=false
[ -f "$WORKSPACE/wt-config.yaml" ] && yaml_exists=true
[ "$yaml_exists" = true ] && [ -n "$(yq -r '.repos | keys | .[]' "$WORKSPACE/wt-config.yaml" 2>/dev/null)" ] && yaml_has_repos=true

mouse_state=$(tmux show -gv mouse 2>/dev/null || echo "unset")
mouse_in_conf=$(grep -E '^[[:space:]]*set(-option)?[[:space:]]+(-g[[:space:]]+)?mouse[[:space:]]+(on|off)' "$HOME/.tmux.conf" 2>/dev/null || true)
```

Then ask the user, in **one** prompt, for whatever decisions are actually needed (skip questions whose answer is already determined):

- **Which repos to register?** Always ask. Accept git URLs and/or local paths (one per line, comma-separated, whatever — be lenient). Empty / "skip" = no repos this run.
- **`wt-config.yaml` already has registered repos** (only if `yaml_has_repos=true`): continue and append, or abort?

Tmux config (mouse + active-window highlighting) is **always written** as a wt-managed block in `~/.tmux.conf` — no question needed. Anything the user has after the block in their conf still wins (tmux applies in file order), so they can override.

After this prompt: every Yes/No / list answer is captured. **No more interactive questions** for the rest of the flow. If the per-repo inference later hits an ambiguity, **auto-pick the best guess and surface it in Phase 3** for the user to review/edit; don't pause to ask.

## Phase 2 — execute everything

Do all the work in order, no prompts. If something fails, stop and report — don't ask "should I continue?".

### 2a. Init `wt-config.yaml`

```bash
if [ ! -f "$WORKSPACE/wt-config.yaml" ]; then
  cp "$WORKSPACE/wt-config.example.yaml" "$WORKSPACE/wt-config.yaml"
fi
```

(If user said "abort" in Phase 1 to the conflict question, you'd have stopped already.)

### 2b. Ensure `env/` exists

```bash
mkdir -p "$WORKSPACE/env"
```

### 2c. Configure tmux (mouse + active-window highlighting)

Maintain a marker-block in `~/.tmux.conf` that wt owns. Always rewrite the block to the latest content; if the user wants to override anything, they can put it AFTER the block (tmux applies in file order, last wins).

The block:

```tmux
# >>> wt-managed (do not edit between markers; bootstrap rewrites this block)
set -g mouse on

# Active-window highlighting — without strong contrast, scanning Ctrl-b w
# across many open worktrees is awful. Colors are catppuccin-mocha; tweak by
# overriding these settings AFTER the wt-managed block in your conf.
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
setw -g window-status-current-format '#[fg=#1e1e2e,bg=#cba6f7]#[fg=#1e1e2e,bg=#cba6f7,bold] #I:#W#F #[fg=#cba6f7,bg=#1e1e2e]'
setw -g window-status-format         '#[fg=#1e1e2e,bg=#313244]#[fg=#cdd6f4,bg=#313244] #I:#W#F #[fg=#313244,bg=#1e1e2e]'
# <<< wt-managed
```

Implementation — replace existing markers if present, else append:

```bash
TMUX_CONF="$HOME/.tmux.conf"
touch "$TMUX_CONF"

BLOCK=$(cat <<'EOF'
# >>> wt-managed (do not edit between markers; bootstrap rewrites this block)
set -g mouse on
set -g status-style 'bg=#1e1e2e fg=#cdd6f4'
setw -g window-status-current-format '#[fg=#1e1e2e,bg=#cba6f7]#[fg=#1e1e2e,bg=#cba6f7,bold] #I:#W#F #[fg=#cba6f7,bg=#1e1e2e]'
setw -g window-status-format         '#[fg=#1e1e2e,bg=#313244]#[fg=#cdd6f4,bg=#313244] #I:#W#F #[fg=#313244,bg=#1e1e2e]'
# <<< wt-managed
EOF
)

if grep -qF '# >>> wt-managed' "$TMUX_CONF"; then
  # Rewrite between the markers (preserve everything outside).
  awk -v block="$BLOCK" '
    /^# >>> wt-managed/ { print block; in_block = 1; next }
    /^# <<< wt-managed/ { in_block = 0; next }
    !in_block
  ' "$TMUX_CONF" > "$TMUX_CONF.tmp" && mv "$TMUX_CONF.tmp" "$TMUX_CONF"
else
  # Append (with a leading blank line if the file isn't empty).
  [ -s "$TMUX_CONF" ] && printf '\n' >> "$TMUX_CONF"
  printf '%s\n' "$BLOCK" >> "$TMUX_CONF"
fi

# Apply each setting to the running server (no-op if no server). Don't
# `source-file` the whole conf — that would re-run binds/hooks too.
tmux set -g mouse on 2>/dev/null || true
tmux set -g status-style 'bg=#1e1e2e fg=#cdd6f4' 2>/dev/null || true
tmux setw -g window-status-current-format '#[fg=#1e1e2e,bg=#cba6f7]#[fg=#1e1e2e,bg=#cba6f7,bold] #I:#W#F #[fg=#cba6f7,bg=#1e1e2e]' 2>/dev/null || true
tmux setw -g window-status-format '#[fg=#1e1e2e,bg=#313244]#[fg=#cdd6f4,bg=#313244] #I:#W#F #[fg=#313244,bg=#1e1e2e]' 2>/dev/null || true
```

Idempotent: re-running rewrites the block to the latest content without disturbing surrounding lines.

### 2d. Register each repo

For each input the user supplied in Phase 1, run the **inference half** of `wt-add-repo` (read its SKILL.md for details — clone or adopt → walk the tree → derive dir / run / setup / ports / env mappings) and **auto-apply** without per-repo approval:

- On any ambiguity (multiple plausible run scripts, multiple ports, multiple app dirs, etc.) — **pick the most obvious candidate** by these tiebreakers:
  - dev script: prefer `dev` > `start` > `serve` (in `package.json scripts`).
  - port: prefer the first one found in `.env.example`/`.env.template`; else the first one in source.
  - app dir: prefer the repo root if a runnable manifest exists there; else the shallowest matching candidate.
- **Record every auto-pick** in a list (`auto_picks`) keyed by repo name, so Phase 3 can surface them.
- Edit `wt-config.yaml` with the Edit tool (NOT `yq -i` — block-scalar formatting matters).
- Touch each env-file source path so the placeholder exists.

Sequential, not parallel — yaml edits would race.

### 2e. Sync shared scripts + mappings

```bash
"$WORKSPACE/wt" sync
```

This symlinks `shared-scripts/*` and applies the new mappings into every canonical and worktree.

## Phase 3 — report

Print a structured summary. No questions, no interactive prompts.

```bash
echo "=== registered repos ==="
yq -r '.repos | keys | .[]' "$WORKSPACE/wt-config.yaml"

echo "=== env files (populate before first ./run) ==="
for f in "$WORKSPACE"/env/.env-*; do
  [ -f "$f" ] || continue
  size=$(wc -c < "$f" | tr -d ' ')
  status=$([ "$size" -eq 0 ] && echo "EMPTY — needs values" || echo "ok ($size bytes)")
  echo "  $(basename "$f") — $status"
done
```

Also print:

- **Auto-picks to review** (one line per ambiguity): "For `<repo>`, picked `run: bun run dev` from candidates `dev|start|serve`. Edit `wt-config.yaml` if wrong."
- Tmux state: "wt-managed block written to `~/.tmux.conf` (mouse + active-window highlight). Override anything by adding lines AFTER the `# <<< wt-managed` marker."
- Next commands: `./wt <repo> <branch>` to spin up a worktree, `/wt-add-repo` to register more repos later.

Don't auto-spawn a worktree.

## Notes

- **All questions in Phase 1, all work in Phase 2.** If you find yourself wanting to ask a question during execution, you missed it in the upfront prompt — fix Phase 1, don't add a mid-flow prompt.
- **Idempotent.** Re-running is safe: 2a no-ops if yaml exists, 2c no-ops if mouse already on, 2d's `wt-add-repo` flow refuses to overwrite without confirmation (already part of its contract).
- **Don't auto-fill env files.** Even when the source has `.env.example` with sample values, leave placeholders empty — secrets must be the user's choice.
- **Auto-picks are recorded, not buried.** Every guess made during inference must appear in Phase 3 so the user can audit.
