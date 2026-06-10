# CLAUDE.md — Carrion project context

Read this first every session. It is the contract for all code written in this repo.

## What this project is

THE LONG WAKE (internal codename: Carrion — repo/class/code identifiers keep the codename; all player-facing strings use "The Long Wake"): asymmetric three-faction zombie-ecosystem RTS, Godot 4.x, GDScript. Competitive multiplayer (up to 6-player FFA) is the end goal, which constrains *how* all code is written (see Determinism Rules).

## Canonical documents — read these as current truth

1. **DESIGN_MASTER.md** — the design source of truth. Supersedes DESIGN_DOC.md and PROTOTYPE_PLAN.md. Items tagged [OPEN] are undecided — ask, don't assume.
2. **AUDIT.md** — full code audit (2026-06-07 baseline) with severity-ranked, file:line findings. Read the status banner at its top first: all Critical/High are FIXED; the D-series determinism sweep is done-or-documented-deferred. Fixed lines carry `FIXED <date>`; when you fix a finding, append `FIXED <date>` to its line.
3. **NETCODE.md** — determinism/netcode decisions + the shipped replay/checksum harness. Canonical for *why* the determinism rules exist.
4. This file — conventions + determinism rules.

## Doc-status map — know what you're reading (the anti-stale-confusion index)

New sessions get confused when they read a dated planning doc as if it were current state. Classify before you trust:

- **CANONICAL** (trust as current; fix in-session if you find them stale): the four above.
- **HISTORICAL — do NOT implement from these** (kept for provenance only): `DESIGN_DOC.md`, `PROTOTYPE_PLAN.md`. Superseded by DESIGN_MASTER.md.
- **SNAPSHOTS — accurate only as of their dateline; later commits may have overtaken them; never treat as current state without checking git/code**: everything in `docs/` (the plan/audit/run-log files), plus `WORKFLOW_PLAYBOOK.md`, `ART_PIPELINE_RESEARCH.md`, `StarCraft_BroodWar_Multiplayer_Reference.md`. These are point-in-time plans, research, and logs. When one conflicts with a CANONICAL doc or the code, the canonical doc and the code win.

Rule of thumb: **staleness in a CANONICAL doc is a bug — fix it the same session. Staleness in a SNAPSHOT is expected — don't act on it, and don't bother rewriting history.**

## Determinism Rules (mandatory for all new/modified gameplay code)

The sim must eventually run lockstep across clients. Every violation written today is a retrofit later.

1. **No bare `randf()`/`randi()`/`randf_range()` in gameplay logic.** All gameplay randomness goes through a single seeded RNG owned by the sim (create `autoloads/SimRng.gd` if it doesn't exist yet: one `RandomNumberGenerator`, match-seeded, with helper methods). Visual-only randomness (particle jitter, sprite variation) may stay local but must never feed back into gameplay state.
2. **Fixed-tick gameplay.** Game logic advances on the physics tick or explicit accumulators — never `_process(delta)` for anything that changes sim state. Rendering/UI may use `_process`.
3. **No physics-engine queries for gameplay decisions** in new code (`intersect_shape`, `intersect_point`, raycasts for targeting/perception). Read the coarse grids instead (ZombieField, NoiseField, DecayField, the planned steering field). Existing physics-query code is grandfathered until its system is touched.
4. **No iteration over `get_nodes_in_group()` where order affects outcomes** unless sorted by a stable key (instance id is not stable across clients — use spawn-ordinal ids).
5. **Float discipline (decided 2026-06-08: float-with-discipline, NOT fixed-point — see NETCODE.md):** avoid accumulating tiny per-frame floats into long-lived gameplay state; prefer integer/fixed-step accumulators where feasible. **No transcendentals (`sin`/`cos`/`atan`/`atan2`/inverse-sqrt) in gameplay math** — they diverge across CPUs and are a latent desync source; use them freely in render/visual code only. Keep the sim layer structured so positions/combat could swap to fixed-point later if cross-machine testing ever demands it.
6. **Sim/render separation:** gameplay state must never read from render state (positions are sim state; sprite offsets, iso projection, z-index are render).

After any batch of gameplay-code changes (anything touching `scripts/*.gd` or `autoloads/*.gd`), invoke the **determinism-reviewer** subagent (`.claude/agents/determinism-reviewer.md`) on the diff BEFORE handing back to the human. It's read-only, scoped to these 6 rules, and reports findings as a tight `file:line — reason` list. The Stop hook handles parse correctness; the reviewer handles determinism correctness.

## Architecture conventions

- **Ownership vs. hostility:** faction (`GameState.Faction`) is *allegiance flavor*; ownership/team is decided by groups (`player_units`/`ai_units`, `player_buildings`/`ai_buildings`). Hostility checks must be team-based, not faction-based (see AUDIT.md H4/H10 — this is currently broken in places; new code must not copy the broken pattern). A shared `is_hostile(a, b)` / `is_owned_by_player(node)` helper should be introduced and used everywhere.
- **Zombie steering:** all zombie movement influences (noise residue, scent, density, anchors, repulsors, home bias) belong in one signed-weight field system per DESIGN_MASTER.md §3.2 — no new bespoke per-unit zombie behaviors.
- **Constants:** map size, tile size, and tile ids are defined once (IsoView / a constants autoload) — never re-hardcode `6144`, `192`, `32.0`, or `50.0..6094.0` (AUDIT.md documents the existing duplication; reduce it when touching those files).
- **Noise emissions** go through `NoiseBus.emit()` at the call site of the action, with a named constant for magnitude. Every unit's noise profile is part of faction balance (Military loud, Tribal near-silent, Survivor silent) — never add or remove an emission casually.
- **Corpse logic** lives in `Unit._should_leave_corpse` / `Corpse.gd`. Design target: 80% corpse chance for non-clean-kill Military deaths, all factions' corpses can rise (DESIGN_MASTER.md §4). Population caps must be enforced at *every* zombie-creation site (horde spawn, corpse rise, lootable spawn, shaman spawn).
- **Telemetry:** when adding gameplay events (kills, salvage, spawns), also emit them to the match-stats log if one exists; if it doesn't yet, leave a `# TELEMETRY:` comment hook.

## Verification expectations

- After any change, run a headless parse check: `godot --headless --check-only` (or open the project headless and confirm no script errors).
- For gameplay fixes, state in your summary *how the fix can be play-verified* (e.g., "spawn a Brawler, right-click the AI HQ, confirm no error and HQ takes damage") — Matt verifies by playing.
- Do not mark an AUDIT.md item fixed without the parse check passing.

## Style

- **Targeted edits only — never rewrite a whole file to change a few lines.** Whole-file rewrites churn line endings (CRLF/LF), destroy diff reviewability, and risk truncation. Preserve each file's existing line endings.
- Match the existing code style: tabs, typed vars where present, explanatory comments for non-obvious mechanics (this codebase comments *why*, keep doing that).
- Prototype-era code may be replaced wholesale when a design system supersedes it, but check DESIGN_MASTER.md first — several "weird" mechanics (the Hunter's passive defensive zombie escort, shoot-to-loot, homeward zombies) are intentional design, not bugs. (Note: the Hunter's old *clicking* mechanic was removed 2026-06-10 — it now binds ≤4 zero-DPS defensive thralls; see DESIGN_MASTER §7.2.)
