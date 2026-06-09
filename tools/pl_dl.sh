#!/usr/bin/env bash
# Helper: download a Pixellab animation's frames into <root>/<action>/<dir>/N.png.
# Source the file and call dl_anim with named-array of dir->anim-uuid and frame count.
#
# Usage:
#   source pl_dl.sh
#   declare -A UUIDS=( [south]="..." [east]="..." ... )
#   dl_anim "$CHAR_ID" "$ROOT_DIR" "$ACTION" "$FRAMES" UUIDS

set -u

ACCT="${PIXELLAB_ACCT:-f2bd1aa7-2c86-4bec-b20e-434a98b4aacc}"

dl_anim() {
    local char_id="$1" root="$2" action="$3" frames="$4"
    local -n uuids="$5"
    local base="https://backblaze.pixellab.ai/file/pixellab-characters/$ACCT/$char_id/animations"
    local ok=0 fail=0
    for dir in "${!uuids[@]}"; do
        local uuid="${uuids[$dir]}"
        local outdir="$root/$action/$dir"
        mkdir -p "$outdir"
        for ((i = 0; i < frames; i++)); do
            local out="$outdir/$i.png"
            if curl -sSf -o "$out" "$base/$uuid/$dir/$i.png"; then
                ok=$((ok + 1))
            else
                fail=$((fail + 1))
                echo "FAIL: $action/$dir/$i.png" >&2
            fi
        done
    done
    echo "[$action] $ok ok / $fail fail"
}
