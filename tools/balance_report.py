#!/usr/bin/env python3
"""
Balance report for The Long Wake match telemetry.

Reads every *.jsonl match log in a directory and prints aggregate stats:
matches analyzed, win rates by side, match duration stats, hordes
fired/suppressed (with suppression reasons), units died by faction, corpses
risen.

Usage:
    python tools/balance_report.py <dir>

The default <dir> is the project's user-data matches directory on Windows.
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable


# Mirrors GameState.Faction in autoloads/GameState.gd. Kept in sync by hand;
# if you reorder the enum there, update here. (The schema_version field in
# match headers lets us catch incompatible changes later.)
FACTION_NAMES = {
    0: "MILITARY",
    1: "TRIBAL",
    2: "ZOMBIE",
    3: "NEUTRAL",
    4: "SURVIVOR",
}


def faction_name(value) -> str:
    if isinstance(value, int):
        return FACTION_NAMES.get(value, f"UNKNOWN({value})")
    return str(value) if value is not None else "UNKNOWN"


def iter_match_files(directory: Path) -> Iterable[Path]:
    for entry in sorted(directory.iterdir()):
        if entry.is_file() and entry.suffix.lower() == ".jsonl":
            yield entry


def load_match(path: Path) -> dict | None:
    """Parse one JSONL match log. Returns None on malformed input."""
    header = None
    events: list[dict] = []
    try:
        with path.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                row = json.loads(line)
                if header is None:
                    header = row
                else:
                    events.append(row)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"  warning: could not parse {path.name}: {exc}", file=sys.stderr)
        return None
    if header is None:
        return None
    return {"path": path, "header": header, "events": events}


def fmt_pct(numerator: int, denominator: int) -> str:
    if denominator == 0:
        return "0.0%"
    return f"{(100.0 * numerator / denominator):.1f}%"


def fmt_duration(sec: float) -> str:
    m, s = divmod(int(sec), 60)
    return f"{m}m{s:02d}s"


def report(directory: Path) -> int:
    if not directory.is_dir():
        print(f"error: {directory} is not a directory", file=sys.stderr)
        return 1

    matches = []
    for path in iter_match_files(directory):
        match = load_match(path)
        if match is None:
            continue
        # match_end is the only event that records the canonical result;
        # discard runs that never finished (the process was killed mid-match).
        end_events = [e for e in match["events"] if e.get("e") == "match_end"]
        if not end_events:
            print(f"  skip {path.name}: no match_end event", file=sys.stderr)
            continue
        match["end"] = end_events[-1]
        matches.append(match)

    if not matches:
        print(f"No completed matches found under {directory}.")
        return 0

    print(f"# Balance report: {directory}")
    print(f"matches analyzed: {len(matches)}")
    print()

    # --- Win rates by side ---------------------------------------------------
    results = Counter()
    winners = Counter()
    for m in matches:
        end = m["end"]
        results[end.get("result", "unknown")] += 1
        winners[end.get("winner_faction", "UNKNOWN")] += 1
    print("## Win rates")
    for result, count in results.most_common():
        print(f"  result={result:<10} {count:>4} ({fmt_pct(count, len(matches))})")
    print()
    print("## Winner side")
    for winner, count in winners.most_common():
        print(f"  {winner:<10} {count:>4} ({fmt_pct(count, len(matches))})")
    print()

    # --- Match duration ------------------------------------------------------
    durations = [
        float(m["end"].get("duration_sim_sec", 0.0))
        for m in matches
        if m["end"].get("duration_sim_sec") is not None
    ]
    if durations:
        print("## Match duration (sim seconds)")
        print(f"  min     {fmt_duration(min(durations))} ({min(durations):.1f}s)")
        print(f"  max     {fmt_duration(max(durations))} ({max(durations):.1f}s)")
        print(f"  mean    {fmt_duration(statistics.mean(durations))} ({statistics.mean(durations):.1f}s)")
        print(f"  median  {fmt_duration(statistics.median(durations))} ({statistics.median(durations):.1f}s)")
        print()

    # --- Hordes --------------------------------------------------------------
    horde_fired = Counter()       # tier -> count
    horde_suppressed = Counter()  # tier -> count
    suppress_reason = Counter()   # reason -> count
    for m in matches:
        for ev in m["events"]:
            etype = ev.get("e")
            if etype == "horde_fired":
                horde_fired[ev.get("tier", "?")] += 1
            elif etype == "horde_suppressed":
                horde_suppressed[ev.get("tier", "?")] += 1
                suppress_reason[ev.get("reason", "?")] += 1
    print("## Hordes")
    total_fired = sum(horde_fired.values())
    total_suppressed = sum(horde_suppressed.values())
    print(f"  fired       {total_fired}")
    for tier, count in sorted(horde_fired.items()):
        print(f"    {tier:<14} {count}")
    print(f"  suppressed  {total_suppressed}")
    for tier, count in sorted(horde_suppressed.items()):
        print(f"    {tier:<14} {count}")
    if suppress_reason:
        print(f"  suppression reasons:")
        for reason, count in suppress_reason.most_common():
            print(f"    {reason:<14} {count}")
    print()

    # --- Units died by faction -----------------------------------------------
    deaths_by_faction = Counter()
    deaths_by_type = Counter()
    left_corpse = 0
    total_deaths = 0
    for m in matches:
        for ev in m["events"]:
            if ev.get("e") != "unit_died":
                continue
            total_deaths += 1
            deaths_by_faction[faction_name(ev.get("faction"))] += 1
            deaths_by_type[ev.get("type", "Unknown")] += 1
            if ev.get("left_corpse"):
                left_corpse += 1
    print("## Unit deaths")
    print(f"  total       {total_deaths}")
    print(f"  with corpse {left_corpse} ({fmt_pct(left_corpse, total_deaths)})")
    print("  by faction:")
    for fac, count in deaths_by_faction.most_common():
        print(f"    {fac:<10} {count}")
    print("  by type:")
    for type_, count in deaths_by_type.most_common():
        print(f"    {type_:<14} {count}")
    print()

    # --- Corpses risen -------------------------------------------------------
    risen = 0
    risen_military = 0
    for m in matches:
        for ev in m["events"]:
            if ev.get("e") != "corpse_rose":
                continue
            risen += 1
            if ev.get("prev_was_military"):
                risen_military += 1
    print("## Corpses risen")
    print(f"  total            {risen}")
    print(f"  from Military    {risen_military}")
    if total_deaths > 0:
        print(f"  rise-per-death   {risen / total_deaths:.2f}")
    print()

    return 0


def default_directory() -> Path:
    # On Windows the project's user-data dir is %APPDATA%/Godot/app_userdata/Carrion Prototype/.
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "Godot" / "app_userdata" / "Carrion Prototype" / "matches"
    return Path.cwd() / "matches"


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate Long Wake match telemetry.")
    parser.add_argument(
        "directory",
        nargs="?",
        default=str(default_directory()),
        help="Directory of *.jsonl match logs. Defaults to %APPDATA%/Godot/app_userdata/Carrion Prototype/matches.",
    )
    args = parser.parse_args()
    return report(Path(args.directory))


if __name__ == "__main__":
    sys.exit(main())
