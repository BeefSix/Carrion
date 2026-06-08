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

    # --- Comparison by dispatch_group_size ----------------------------------
    # When the matches dir contains a sweep across dispatch values, lead with
    # the side-by-side table so the operator sees the answer first. Falls back
    # silently if all matches share one setting (or none recorded the value).
    _print_dispatch_comparison(matches)

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


def _print_dispatch_comparison(matches: list[dict]) -> None:
    """Comparison table across dispatch_group_size settings, sweep-style."""
    groups: dict = {}
    for m in matches:
        dgs = m["header"].get("constants", {}).get("dispatch_group_size")
        groups.setdefault(dgs, []).append(m)
    # Only emit the comparison if multiple settings are present (sweep) AND
    # at least one of them is an integer (i.e. not all None).
    int_keys = [k for k in groups.keys() if isinstance(k, int)]
    if len(int_keys) < 2:
        return
    int_keys.sort()
    print("## Comparison by ATTACK_DISPATCH_GROUP_SIZE")
    rows: list[tuple[str, list[str]]] = []

    def add_row(label: str, fn) -> None:
        rows.append((label, [fn(groups[k]) for k in int_keys]))

    add_row("matches", lambda ms: str(len(ms)))
    add_row(
        "victory rate",
        lambda ms: fmt_pct(sum(1 for m in ms if m["end"].get("result") == "victory"), len(ms)),
    )
    add_row(
        "timeout rate",
        lambda ms: fmt_pct(sum(1 for m in ms if m["end"].get("result") == "timeout"), len(ms)),
    )
    def mean_duration(ms):
        durations = [float(m["end"].get("duration_sim_sec", 0.0)) for m in ms]
        return f"{statistics.mean(durations):.0f}s" if durations else "-"
    add_row("mean duration", mean_duration)

    # Human deaths split by cause: filter out faction=ZOMBIE on the victim
    # (we want non-zombie unit_died events) then bucket by `cause`.
    def deaths_by_cause(ms, target_cause):
        n = 0
        for m in ms:
            for ev in m["events"]:
                if ev.get("e") != "unit_died":
                    continue
                if ev.get("faction") == "ZOMBIE":
                    continue
                if ev.get("cause") == target_cause:
                    n += 1
        return n
    def total_human_deaths(ms):
        return sum(
            1
            for m in ms
            for ev in m["events"]
            if ev.get("e") == "unit_died" and ev.get("faction") != "ZOMBIE"
        )
    add_row("human deaths", lambda ms: str(total_human_deaths(ms)))
    for cause in ("zombie", "enemy", "friendly", "unknown"):
        add_row(f"  by {cause}", lambda ms, c=cause: str(deaths_by_cause(ms, c)))

    # Column-aligned print. Label column is left-padded to the longest label;
    # value columns are right-aligned to a fixed width.
    label_w = max(len(r[0]) for r in rows)
    col_w = 10
    header_cells = [f"size={k:<2}".rjust(col_w) for k in int_keys]
    print(f"{'':<{label_w}}  " + "".join(header_cells))
    for label, values in rows:
        print(f"{label:<{label_w}}  " + "".join(v.rjust(col_w) for v in values))
    print()


def default_directory() -> Path:
    # On Windows the project's user-data dir is %APPDATA%/Godot/app_userdata/Carrion Prototype/.
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "Godot" / "app_userdata" / "Carrion Prototype" / "matches"
    return Path.cwd() / "matches"


def _print_timeline(match_path: Path) -> int:
    """--timeline mode: chronological AI decision log for both controllers."""
    match = load_match(match_path)
    if match is None:
        print(f"error: could not parse {match_path}", file=sys.stderr)
        return 1
    header = match["header"]
    matchup = header.get("matchup", {})
    is_ava = header.get("ai_vs_ai", False)
    dgs = header.get("constants", {}).get("dispatch_group_size", "?")
    print(f"# Timeline: {match_path.name}")
    print(
        f"# matchup: player={matchup.get('player', '?')} ai={matchup.get('ai', '?')} "
        f"(ai_vs_ai={is_ava})  dispatch_group_size={dgs}  seed={header.get('seed', '?')}"
    )
    end = next((e for e in reversed(match["events"]) if e.get("e") == "match_end"), None)
    if end is not None:
        print(
            f"# outcome: {end.get('result', '?')} winner={end.get('winner_faction', '?')} "
            f"duration_sim_sec={end.get('duration_sim_sec', 0):.0f}"
        )
    print()
    print(f"{'sim_t':>9}  {'ctrl':<7}  {'event':<22}  details")
    print(f"{'-'*9}  {'-'*7}  {'-'*22}  {'-'*40}")
    # AI-side event vocabulary
    AI_EVENTS = {
        "ai_phase",
        "ai_posture_changed",
        "ai_attack_ordered",
        "ai_unit_dispatched",
    }
    # Stable order on ties: posture/order/dispatch events first, snapshots
    # second, so a single t reads "decision then state".
    EVENT_SORT_ORDER = {
        "ai_posture_changed": 0,
        "ai_attack_ordered": 1,
        "ai_unit_dispatched": 2,
        "ai_phase": 3,
    }
    rows = []
    for ev in match["events"]:
        if ev.get("e") not in AI_EVENTS:
            continue
        rows.append(ev)
    rows.sort(key=lambda e: (float(e.get("t", 0.0)), EVENT_SORT_ORDER.get(e.get("e"), 99)))
    if not rows:
        print("(no AI decision events found - was this match run after the AI telemetry was wired?)")
        return 0
    for ev in rows:
        t = float(ev.get("t", 0.0))
        ctrl = ev.get("controller", "?")
        etype = ev.get("e", "?")
        if etype == "ai_phase":
            details = (
                f"step={ev.get('step', '?')} state={ev.get('state', '?')} "
                f"sal={ev.get('salvage', '?')} looters={ev.get('looters', '?')} "
                f"combat={ev.get('combat', '?')} barracks={ev.get('has_barracks', '?')}"
            )
        elif etype == "ai_posture_changed":
            details = f"{ev.get('from', '?')} -> {ev.get('to', '?')}"
        elif etype == "ai_attack_ordered":
            tp = ev.get("target_pos", [0, 0])
            details = f"target=[{tp[0]:.0f},{tp[1]:.0f}] army_size={ev.get('army_size', '?')}"
        elif etype == "ai_unit_dispatched":
            details = f"count={ev.get('count', '?')}"
        else:
            details = json.dumps({k: v for k, v in ev.items() if k not in ("t", "e", "controller")})
        print(f"{t:>9.1f}  {ctrl:<7}  {etype:<22}  {details}")
    # Summary at the bottom answers the operator's question without scanning.
    print()
    reached_attack = {c: any(e.get("e") == "ai_posture_changed" and e.get("controller") == c and e.get("to") == "ATTACK"
                              for e in rows)
                       for c in ("player", "ai")}
    last_state = {}
    for ev in rows:
        if ev.get("e") == "ai_phase":
            last_state[ev.get("controller")] = ev.get("state")
    print("## Summary")
    for ctrl in ("player", "ai"):
        if reached_attack[ctrl]:
            atks = [e for e in rows
                    if e.get("e") == "ai_attack_ordered" and e.get("controller") == ctrl]
            first = atks[0] if atks else None
            if first is not None:
                tp = first.get("target_pos", [0, 0])
                print(
                    f"  {ctrl}: REACHED ATTACK at t={float(first.get('t', 0.0)):.1f}s  "
                    f"target=[{tp[0]:.0f},{tp[1]:.0f}] army_size={first.get('army_size', '?')}"
                )
            else:
                print(f"  {ctrl}: REACHED ATTACK (no order recorded?)")
        else:
            print(f"  {ctrl}: NEVER attacked. last observed state={last_state.get(ctrl, '?')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate Long Wake match telemetry.")
    parser.add_argument(
        "directory",
        nargs="?",
        default=str(default_directory()),
        help="Directory of *.jsonl match logs. Defaults to %APPDATA%/Godot/app_userdata/Carrion Prototype/matches.",
    )
    parser.add_argument(
        "--timeline",
        metavar="MATCH_JSONL",
        help="Single-match mode: print a chronological side-by-side AI decision log for the given .jsonl file.",
    )
    args = parser.parse_args()
    if args.timeline:
        return _print_timeline(Path(args.timeline))
    return report(Path(args.directory))


if __name__ == "__main__":
    sys.exit(main())
