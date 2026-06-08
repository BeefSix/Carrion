#!/usr/bin/env python3
"""
Balance sweep orchestrator for The Long Wake.

Runs the AI-vs-AI headless mode N times, varying a parameter (default:
ATTACK_DISPATCH_GROUP_SIZE via --dispatch-group-size) across a grid of seeds.
Each invocation writes its own JSONL log into the project's user matches dir;
tools/balance_report.py aggregates them.

Sequential: parallel Godot processes could collide on user://matches filenames
(seconds-resolution wallclock). 30 matches at the AI-vs-AI 8x time_scale take
~7.5 sim min worst case = ~1 wall min per stalemate, ~30 sec for decisive runs.

Usage:
    python tools/balance_sweep.py
    python tools/balance_sweep.py --dispatch 2 3 4 --seeds 1 2 3 4 5
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT_EXE = ROOT / ".tools" / "godot" / "Godot_v4.6.3-stable_win64_console.exe"

DEFAULT_DISPATCH = [2, 3, 4]
DEFAULT_SEEDS = list(range(1, 11))


def run_match(dispatch: int, seed: int) -> tuple[int, float, str]:
    args = [
        str(GODOT_EXE),
        "--headless",
        "--path", str(ROOT),
        "--",
        "--ai-vs-ai",
        f"--seed={seed}",
        f"--dispatch-group-size={dispatch}",
    ]
    t0 = time.time()
    proc = subprocess.run(args, capture_output=True, text=True)
    elapsed = time.time() - t0
    # Extract the match log path from stdout for the operator's bread crumb.
    log_path = ""
    for line in proc.stdout.splitlines():
        if "[MatchStats] match log closed" in line:
            log_path = line.split(":", 1)[-1].strip()
            break
    return proc.returncode, elapsed, log_path


def main() -> int:
    p = argparse.ArgumentParser(description="Run a balance sweep of AI-vs-AI headless matches.")
    p.add_argument("--dispatch", nargs="+", type=int, default=DEFAULT_DISPATCH,
                   help=f"Dispatch group sizes to test (default {DEFAULT_DISPATCH})")
    p.add_argument("--seeds", nargs="+", type=int, default=DEFAULT_SEEDS,
                   help=f"Match seeds (default {DEFAULT_SEEDS})")
    args = p.parse_args()

    if not GODOT_EXE.exists():
        print(f"error: {GODOT_EXE} not found", file=sys.stderr)
        return 1

    total = len(args.dispatch) * len(args.seeds)
    print(f"Sweep: {total} matches via {GODOT_EXE.name}")
    print(f"  dispatch values: {args.dispatch}")
    print(f"  seeds:           {args.seeds}")
    print()

    done = 0
    t_start = time.time()
    failures: list[tuple[int, int, int]] = []
    for d in args.dispatch:
        for s in args.seeds:
            rc, dt, log_path = run_match(d, s)
            done += 1
            elapsed = time.time() - t_start
            avg = elapsed / done
            eta = avg * (total - done)
            tag = "OK" if rc == 0 else f"FAIL({rc})"
            print(
                f"  [{done:>2}/{total}] dispatch={d} seed={s:>2} {tag} "
                f"({dt:.1f}s wall) elapsed={elapsed:.0f}s eta={eta:.0f}s",
                flush=True,
            )
            if log_path:
                print(f"           {log_path}", flush=True)
            if rc != 0:
                failures.append((d, s, rc))

    total_elapsed = time.time() - t_start
    print()
    print(f"Sweep complete: {done} matches in {total_elapsed:.0f}s wall "
          f"({total_elapsed/60:.1f} min); {len(failures)} failures.")
    if failures:
        for d, s, rc in failures:
            print(f"  FAIL dispatch={d} seed={s} exit={rc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
