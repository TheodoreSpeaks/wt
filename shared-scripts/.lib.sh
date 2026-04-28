# Helpers shared by run / kill / rm. Sourced, not executed (no exec bit, so
# wt's sync-scripts loop skips it via the `-x` test).

# Echo the registered repo name for the current cwd, or empty + nonzero on miss.
# Looks for cwd's git toplevel matching either <workspace>/<name> (canonical)
# or <workspace>/<name>-wt/<...> (worktree).
detect_repo_from_cwd() {
  local workspace="$1" top rel name
  top=$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null) || return 1
  case "$top" in
    "$workspace"/*) ;;
    *) return 1 ;;
  esac
  rel="${top#"$workspace"/}"
  if [[ "$rel" == *-wt/* ]]; then
    name="${rel%%-wt/*}"
  else
    name="${rel%%/*}"
  fi
  [ -d "$workspace/$name/.git" ] || return 1
  echo "$name"
}
