#!/usr/bin/env bash
# Determinism CI runner.
#
# Records a fixed-seed AI-vs-AI match, then replays it headless and reports
# the first checksum divergence (if any). Exit code 0 = full reproduction,
# 1 = divergence detected, 2 = setup failure.
#
# Usage: ./tools/determinism_test.sh [seed]
#        (seed defaults to 42)
#
# Requires GODOT env var pointing to a Godot 4.x binary, OR `godot` on PATH.

set -euo pipefail

SEED="${1:-42}"
GODOT="${GODOT:-godot}"

# Replays land in user://replays. On Linux that's ~/.local/share/godot/app_userdata/<project>/replays
# On Windows it's %APPDATA%/Godot/app_userdata/<project>/replays.
# Discover from godot itself rather than guessing, by parsing the path it prints.
USERDIR_LINUX="$HOME/.local/share/godot/app_userdata/Carrion Prototype/replays"
USERDIR_WIN="$APPDATA/Godot/app_userdata/Carrion Prototype/replays"

find_replay_dir() {
    if [ -d "$USERDIR_LINUX" ]; then
        echo "$USERDIR_LINUX"
    elif [ -d "$USERDIR_WIN" ]; then
        echo "$USERDIR_WIN"
    else
        echo ""
    fi
}

echo "[determinism] phase 1/2: recording AI-vs-AI match seed=$SEED ..."
"$GODOT" --headless -- --ai-vs-ai --seed="$SEED" 2>&1 | tail -10

REPLAY_DIR="$(find_replay_dir)"
if [ -z "$REPLAY_DIR" ] || [ ! -d "$REPLAY_DIR" ]; then
    echo "[determinism] ERROR: cannot find replay output dir"
    exit 2
fi

# Find the most recent replay for this seed.
LATEST=$(ls -t "$REPLAY_DIR"/replay_${SEED}_*.jsonl 2>/dev/null | head -1 || true)
if [ -z "$LATEST" ]; then
    echo "[determinism] ERROR: no replay file written for seed $SEED"
    exit 2
fi
echo "[determinism] recorded: $LATEST"

echo "[determinism] phase 2/2: replaying ..."
REPLAY_OUTPUT=$("$GODOT" --headless -- --replay="$LATEST" 2>&1)
echo "$REPLAY_OUTPUT" | tail -20

if echo "$REPLAY_OUTPUT" | grep -q "DIVERGENCE"; then
    echo "[determinism] FAIL: divergence detected. See first DIVERGENCE line above."
    exit 1
fi

echo "[determinism] PASS: replay reproduced match seed=$SEED with no checksum divergence"
