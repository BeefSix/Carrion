# CLAUDE.md — Carrion project context

Read this first every session. It is the contract for all code written in this repo.

## What this project is

Carrion: asymmetric three-faction zombie-ecosystem RTS, Godot 4.x, GDScript. Competitive multiplayer (up to 6-player FFA) is the end goal, which constrains *how* all code is written (see Determinism Rules).

## Canonical documents — in priority order

1. **DESIGN_MASTER.md** — the design source of truth. Supersedes DESIGN_DOC.md and PROTOTYPE_PLAN.md (historical only; do not implement from them). Items tagged [OPEN] are undecided — ask, don't assume.
2. **AUDIT.md** — full code audit (2026-06-07) with ~70 findings, severity-ranked, file:line referenced. When you fix a finding, append `FIXED <date>` to its line in AUDIT.md.
3. This file — conventions.

## Determinism Rules (mandatory for all new/modified gameplay code)

The sim must eventually run lockstep across clients. Every violation written today is a retrofit later.

1. **No bare `randf()`/`randi()`/`randf_range()` in gameplay logic.** All gameplay randomness goes through a single seeded RNG owned by the sim (create `autoloads/SimRng.gd` if it doesn't exist yet: one `RandomNumberGenerator`, match-seeded, with helper methods). Visual-only randomness (particle jitter, sprite variation) may stay local but must never feed back into gameplay state.
2. **Fixed-tick gameplay.** Game logic advances on the physics tick or explicit accumulators — never `_process(delta)` for anything that changes sim state. Rendering/UI may use `_process`.
3. **No physics-engine queries for gameplay decisions** in new code (`intersect_shape`, `intersect_point`, raycasts for targeting/perception). Read the coarse grids instead (ZombieField, NoiseField, DecayField, the planned steering field). Existing physics-query code is grandfathered until its system is touched.
4. **No iteration over `get_nodes_in_group()` where order affects outcomes** unless sorted by a stable key (instance id is not stable across clients — use spawn-ordinal ids).
5. **Float discipline:** avoid accumulating tiny per-frame floats into long-lived gameplay state; prefer integer/fixed-step accumulators where feasible.
6. **Sim/render separation:** gameplay state must never read from render state (positions are sim state; sprite offsets, iso projection, z-index are render).

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
- Prototype-era code may be replaced wholesale when a design system supersedes it, but check DESIGN_MASTER.md first — several "weird" mechanics (clicking Hunters, shoot-to-loot, homeward zombies) are intentional design, not bugs.
