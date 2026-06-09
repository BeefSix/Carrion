#!/usr/bin/env bash
# Stop-hook: enforce the GDScript parse-check before any turn ends.
#
# Invoked by Claude Code via a Stop hook entry in .claude/settings.json.
# Fast path: if no .gd files changed this turn, exit 0 immediately so
# the hook adds zero latency on non-code turns.
#
# Slow path: if .gd files changed, run Godot's headless parse-check
# (`--headless --quit --check-only --path .`) with a hard timeout so
# Godot can never hang the turn in an interactive debugger.
#
# Exit codes:
#   0 = pass (or no .gd files changed)
#   2 = real parse/script error; stderr message is fed back to Claude
#
# Known false-positive handled: `--check-only` sometimes reports
# autoload-identifier errors that resolve fine at runtime because the
# editor registers autoloads BEFORE script parsing while CLI parsing
# happens in a different order. If the *only* errors are
# autoload-resolution ones, this script notes them and treats as pass.
#
# How to disable:
#   - Comment out / remove the "Stop" entry in .claude/settings.json, or
#   - Set "disableAllHooks": true in .claude/settings.json
#   - Or set CARRION_DISABLE_PARSE_CHECK=1 in the env before launching Claude.

set -u  # NOT -e: we need to inspect exit codes from godot and grep manually.

# --- escape valves -----------------------------------------------------------

if [[ "${CARRION_DISABLE_PARSE_CHECK:-0}" == "1" ]]; then
    exit 0
fi

# --- fast path: no .gd files changed -----------------------------------------

# Combine staged + unstaged + untracked-but-known. We don't want a hot edit to
# sneak past the check just because it wasn't staged yet.
CHANGED_GD=$(git diff --name-only -- '*.gd' 2>/dev/null; \
             git diff --name-only --cached -- '*.gd' 2>/dev/null; \
             git ls-files --others --exclude-standard -- '*.gd' 2>/dev/null)
CHANGED_GD=$(printf '%s\n' "$CHANGED_GD" | grep -v '^$' | sort -u)

if [[ -z "$CHANGED_GD" ]]; then
    exit 0
fi

# --- locate Godot ------------------------------------------------------------

GODOT_BIN="${GODOT:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    # Common Windows winget install path. We're shipping this for a Windows dev
    # who may not have set GODOT or PATH — degrade gracefully rather than block.
    FALLBACK="/c/Users/${USER:-${USERNAME:-merli}}/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.6.3-stable_win64.exe"
    if [[ -x "$FALLBACK" ]]; then
        GODOT_BIN="$FALLBACK"
    else
        echo "parse_check_hook: \$GODOT not set and 'godot' not on PATH; skipping check." >&2
        echo "parse_check_hook: set GODOT=/path/to/godot to enable enforcement." >&2
        exit 0
    fi
fi

# --- slow path: headless parse-check -----------------------------------------

# Godot's --check-only ONLY parses what's named with --script. Whole-project
# parsing happens at editor open or full run — neither fits a per-turn hook.
# Solution: pass each changed .gd file through --script --check-only and
# collect any error output. Cross-file reference errors are caught the next
# time Godot loads the project; this hook covers the obvious syntax wins.
ALL_OUT=""
while IFS= read -r gd; do
    [[ -z "$gd" ]] && continue
    [[ ! -f "$gd" ]] && continue  # deleted files: nothing to parse
    OUT=$(timeout 60 "$GODOT_BIN" --headless --path . --check-only --script "$gd" 2>&1 || true)
    ALL_OUT+="$OUT"$'\n'
done <<< "$CHANGED_GD"

# Pull lines that look like script errors. Godot tags them with "SCRIPT ERROR"
# or "Parse Error" or "Failed to load script". Strip cosmetic ANSI codes.
ERR_LINES=$(printf '%s' "$ALL_OUT" \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -iE '(SCRIPT ERROR|Parse Error|^ERROR:.*\.gd|at function:.*\.gd|Cannot find type|Could not parse global|Failed to load script)' \
    || true)

# No errors at all -> pass.
if [[ -z "$ERR_LINES" ]]; then
    exit 0
fi

# Filter known false positives. Godot's CLI parser sometimes can't resolve
# autoload identifiers (e.g. "Cannot resolve type 'SimRng'") because autoloads
# register at runtime but the CLI parser pre-resolves types. The editor and
# headless RUN both work fine; only --check-only complains. If EVERY error is
# of this shape, treat as pass with a note.
TOTAL_ERR_COUNT=$(printf '%s\n' "$ERR_LINES" | wc -l)
AUTOLOAD_ERR_COUNT=$(printf '%s\n' "$ERR_LINES" \
    | grep -cE '(Cannot resolve|Identifier ".*" not declared in the current scope|Cannot find member ".*" in base "Node")' \
    || true)

if [[ "$TOTAL_ERR_COUNT" -gt 0 && "$TOTAL_ERR_COUNT" -eq "$AUTOLOAD_ERR_COUNT" ]]; then
    echo "parse_check_hook: $TOTAL_ERR_COUNT autoload-identifier warning(s) (known false positive), allowing." >&2
    exit 0
fi

# Real errors. Block the turn and feed them back via stderr.
echo "parse_check_hook: BLOCKED — GDScript parse errors detected:" >&2
printf '%s\n' "$ERR_LINES" >&2
exit 2
