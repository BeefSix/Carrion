# CARRION — Full Project Audit

*Audited 2026-06-07. Scope: all 40 GDScript files (~10.8k lines), 30 scenes, project config, DESIGN_DOC.md, PROTOTYPE_PLAN.md. Severity: Critical = crash/blocks core loop; High = materially distorts gameplay or will bite players soon; Medium = real but contained; Low = hygiene/polish.*

## Executive summary

The codebase is in better shape than most prototypes — well-commented, with visible evidence of past perf passes (throttled engagement checks, occluder caches, spatial indexes, projectile raycast fix). But the audit found **1 crash bug, ~14 High-severity issues, and a deep drift between what the prototype plan committed to and what was built**. Three themes dominate:

1. **Ownership vs. faction confusion.** Hostility is decided by `faction`, ownership by groups (`ai_units`/`player_units`). This breaks the Military-mirror matchup outright (armies can't shoot each other), lets the player select and operate enemy buildings, and lets projectiles chip friendly walls.
2. **Optimization lessons applied unevenly.** The base class documents fixing the O(N²) engagement scan, yet Scout re-introduces a 60 Hz full-group scan, idle gatherers re-scan the lootable group every frame, and NoiseField runs occlusion math for every zombie on the map before any range check.
3. **The prototype lost its thesis.** The plan's verdict apparatus (hot-seat, match-start state, decision doc) is missing, while ~907 art assets, a 1,413-line map generator, a third faction, squads, and veterancy — all explicitly out of scope — were built. The "soul of the game" mechanic (enhanced returns) fires on at most 30% of military combat deaths and never for the Looter.

---

## 1. Critical

**C1 — Brawler crashes when meleeing a building.** `Brawler.gd:45,65` calls `_target.take_damage(dmg, self)` but `Building.take_damage` (`Building.gd:50`) takes one argument. Brawler's target fallback returns HQs, so closing on an enemy HQ throws a runtime error — on the Survivor win-condition path. Fix: add `attacker = null` param to `Building.take_damage` (also fixes the no-XP-from-buildings inconsistency). FIXED 2026-06-07

## 2. High

### Gameplay-loop breakers
- **H1 — Engineer wall-build soft-lock.** `Engineer.gd:63-67, 241-251`: a move order during `Sub.CONSTRUCTING` overwrites `_nav.target_position`; after arriving, `_tick_constructing` calls `_follow_navigation()` toward an already-reached target forever. 25 salvage lost, Engineer permanently unable to build. Fix: re-set `_nav.target_position = _wall_target` when out of range. FIXED 2026-06-07
- **H2 — AI hard-stalls permanently.** `AIStrategist.gd:16-24, 43-56`: strictly sequential build order with no recovery. If both starting Looters die before 200 salvage banks, the AI does nothing for the rest of the match. Same stall if its Barracks is destroyed. FIXED 2026-06-07
- **H3 — AI tactician stomps unit micro.** `AITactician.gd:31-42` re-issues `move_to()` to every combat unit at 1 Hz, snapping them back to MOVE mid-fight (no kiting in MOVE state), re-pathing every unit every second, and trickle-feeding fresh spawns solo across the map. FIXED 2026-06-07
- **H4 — Military vs AI-Military: units can't fight each other.** `Main.gd:295` sets AI faction to MILITARY; targeting (`Rifleman.gd:146` et al.) skips same-faction units. Two armies walk through each other and only snipe HQs. Fix: ownership-based hostility (groups or team id), not faction. FIXED 2026-06-07
- **H5 — Horde tiers eaten by cooldown.** `NoiseField.gd:138-149, 171-185`: `tiers_fired` is set *before* `_maybe_trigger_horde` checks the 30 s cooldown/pop cap, so sustained heavy fire during cooldown produces no horde for that entire noise excursion. This directly undermines the Heavy-Gunner-anxiety thesis. Fix: only consume the flag when the horde actually fires. FIXED 2026-06-07
- **H6 — Clustered zombies go blind.** `Shambler.gd:1290`: vision `intersect_shape(_vision_query, 16)` on the shared unit layer — in a 16+ zombie cluster all result slots fill with zombies and real targets are never seen. Fix: separate collision layer for non-zombies or raise the cap. FIXED 2026-06-07

### Crashes & input correctness (UI layer)
- **H7 — Freed-unit crash on squad creation.** `SquadManager.gd:102` reads `units[0].faction` before validity filtering; dead units are never pruned from the selection (`SelectionManager.gd`, `Unit._die` doesn't notify). Pressing G after the first-selected unit died = freed-instance error. Fix: filter first; prune selection via `tree_exiting`. FIXED 2026-06-07
- **H8 — Phantom selection after wall placement.** `SelectionManager.gd:106-115`: LMB-release branch has no `if _dragging` guard; the release after a consumed wall-placement press finalizes a selection with stale drag coords, typically clearing your Engineer selection. FIXED 2026-06-07
- **H9 — Squad rename re-entrancy creates ghost rows.** `SquadSidebar.gd:185-199, 293-294`: Enter → refresh frees the LineEdit → `focus_exited` fires → re-entrant refresh appends a duplicate row. Disconnect `focus_exited` before refreshing or guard with a flag. FIXED 2026-06-07
- **H10 — Player can operate enemy buildings.** `SelectionManager.gd:247-249` selects any `"buildings"` member; `HUD.gd:130-133` runs `do_action` with no ownership gate. Also right-click repair targets enemy buildings (`SelectionManager.gd:160-161`). Fix: one shared "is this mine / is this hostile" helper used by SelectionManager, HUD, and Projectile. FIXED 2026-06-07
- **H11 — AI production dereferences freed HQ.** `AIController.gd:148-160`: `_hq.position` with no `is_instance_valid` guard; production keeps ticking after the player destroys the AI HQ. FIXED 2026-06-07

### Performance (scale-dependent, hits late-game)
- **H12 — NoiseField occlusion for every zombie–emitter pair.** `NoiseField.gd:209-213`: full attenuation math (occluder loop + segment intersects) runs for all ~300 zombies per emitter every 0.4 s; the range cutoff happens *afterwards* in `Shambler.hear_noise`. Fix: skip pairs beyond hearing range (704 px) first. FIXED 2026-06-07
- **H13 — Scout scans the full units group at 60 Hz.** `Scout.gd:72, 129-137`: unthrottled zombie-detection scan (every other combat unit polls at 2-5 Hz). 4 scouts ≈ 72k distance checks/sec. Same pattern: Walker/Scout idle gatherers re-scan the whole `lootable` group every physics frame when nothing is found (`Walker.gd:38-42`, `Scout.gd:79-83`) — add a retry cooldown. FIXED 2026-06-07
- **H14 — Occluder cache no longer covers hearing range.** `NoiseField.gd:21` caches occluders to 612 px but hearing was bumped to 704 px (`Shambler.gd:20`) — distant zombies hear through walls. Derive the cache radius from the hearing constant. FIXED 2026-06-07

## 3. Medium

### Zombie / noise / corpse systems
- Hordes also fire on *downward* intensity crossings — one huge noise event can fire up to 4 hordes as it decays through tiers (`NoiseField.gd:138-149`).
- Catastrophic waves spawn up to 225 zombies in one frame and overshoot the 300 cap to ~524 (`NoiseField.gd:187-191, 283-291`). Clamp to remaining headroom and stagger spawns.
- Corpse rises bypass the population cap, and dead zombies leave corpses that re-rise — an unbounded recycle loop damped only by `corpse_base_chance` (`Corpse.gd:49-63`, `Unit.gd:291`).
- Tribal-alignment only works if the flag is set before `add_child` (`Shambler.gd:295-298`); any future caller that sets it after insertion silently gets a wild zombie that aggros Tribal. Convert to an explicit `align_to_tribal()` method.
- Chase retention reuses stochastic detection fuzz, so zombies thrash out of CHASE at range ~60% of ticks; the intended `LOST_TARGET_RANGE` hysteresis constant is dead code (`Shambler.gd:68, 1233-1239`). FIXED 2026-06-08
- Faint noises (neighbor moans) cancel target acquisition mid-commit (`Shambler.gd:365-368` — add ACQUIRING to the guard); stale pending cascades fire minutes later (`Shambler.gd:644-651`). FIXED 2026-06-08 (ACQUIRING added to `investigate()` guard; cascade system removed entirely, replaced by damage-driven groan + proximity acquire).

### Units & buildings
- Brawler melee range (36 px to building *center*) can't reach larger HQ footprints — endless shoving (`Brawler.gd:3, 41-49`). Compare against footprint edge.
- Shaman: cost checked only *after* the 5 s channel (silent fizzle), would debit the human player's pool if AI-run (`Shaman.gd:68-77`), and its channel status text is dead code — method named `get_status_text_for_hud` but HUD calls `get_status_text` (`Shaman.gd:90`).
- Looter's defensive fire is instant hitscan while its hunt fire uses projectiles — same weapon, two damage models (`Looter.gd:339-348`).
- Scout cap counts only spawned scouts (and globally, including enemies) — queue-spam bypasses the cap of 4 (`Safehouse.gd:46-58`, `SettlementHub.gd:75-91`).
- SettlementHub action indices shift when a Workshop appears/dies between render and click — UI desync (`SettlementHub.gd:30-35`).
- Engineer flee overrides explicit player orders, silently drops repair tasks, and `Sub.FLEE` has no match arm so it falls into the combat tick (`Engineer.gd:163-186`).
- Combat helpers (`_find_nearest_hostile_hq` ×4, `_kite_from` ×3, sprite builders ×2) are copy-pasted and already diverging (Hunter doesn't corpse-kite; kite speeds differ). Consolidate into Unit.gd or a CombatUnit class.

### Projectiles & camera
- Projectiles damage own-faction buildings, friendly walls block friendly shots, and AOE rounds do zero splash when impacting a building (`Projectile.gd:145-148, 181-195`). The 8-friendly-hop cap teleports the projectile past real targets (`Projectile.gd:138, 167`).
- Camera has no map bounds and WASD pans while typing in the squad-rename box (`RTSCamera.gd:19-30`). Clamp to the iso diamond; early-return when a Control has focus.

### AI & map generation
- Vertical alley probability is inverted — `> 0.10` vs the horizontal `> 0.90` (`TownPlanner.gd:723, 738`); N–S alleys almost never spawn.
- Alleys paint over primary roads, sidewalks, and building footprints with no tile guard (`TownPlanner.gd:846-864`).
- `lots[]`/`buildings[]` are paired by index but `buildings` is a compacted array — any future placement failure silently shifts every later pipeline step (`TownPlanner.gd:479-485, 585-594, 949-959, 1241-1247`).
- Spawn coordinates disagree three ways (TownPlanner anchor tile 168, connector road 176, Main spawns at tile 160 — the *corner* of the cleared zone) (`TownPlanner.gd:47-50` vs `Main.gd:25-28`). Export spawn anchors from `plan_town()` and consume them in Main.
- Map seed is hardcoded to 1 — every procedural match is the identical town (`TownPlanner.gd:93`, `Main.gd:160`). The lootable-infestation RNG is also seeded 1 (`Main.gd:480-481`).
- AI Barracks placed blind at HQ+(140,0) with no validation; AI HQ never triggers a nav rebake at match start, so units path through it for the first ~70 s (`AIController.gd:158-164`, `Main.gd:162-167`).
- AI duplicates player costs/build-times as hand-matched constants — any rebalance silently desyncs it (`AIStrategist.gd:16-28` vs `CommandPost.gd:111-126`).
- TownPlanner step 11 promises infested-building marking but only emits lootables; `step_12_validate` can't actually fail (`TownPlanner.gd:16, 1348-1413`).

### Base class & Main (this pass)
- **Walls are excluded from the navmesh** (`Main.gd:427-428`) but are solid StaticBody2D — pathfinding routes *through* wall lines and units grind against them indefinitely. If intentional (avoid navmesh fragmentation), it needs RVO or a repath fallback; right now player walls create permanent unit traffic jams.
- `toggle_stance()` only cycles AGGRESSIVE↔PASSIVE; a NEUTRAL unit (set via squad posture) silently becomes AGGRESSIVE on toggle (`Unit.gd:111-112`).
- Edge-wanderer keepout only checks the *player* spawn; ambient zombies can dump directly on the AI corner, and after 8 failed attempts the last position is used even inside the keepout (`Main.gd:367-385`).

## 4. Low (compact list)

- Cost is spent even when a producer's unit scene export is null, and queued items aren't refunded when the producer dies — all 8 production buildings (`Barracks.gd:72-79` pattern).
- Queued sub-buildings spawn exactly stacked at fixed offsets — two Barracks overlap perfectly (`CommandPost.gd:124`, `TribalCamp.gd:127,133`).
- Wall cost spent before `build_wall_at` can fail; can't-afford exits placement silently (`SelectionManager.gd:44-49`).
- Dead code: `_cluster_bias_target` + 7 constants (~60 lines — note this was the only anti-blob repel logic; `Shambler.gd:1101-1152`) — REPLACED 2026-06-08 by per-frame boids separation in `Shambler._compute_separation`; `LOST_TARGET_RANGE`, Wall auto-connect (`Wall.gd:31-48`), `HUD.MAX_ACTIONS`, `projectile_impacted` signal never emitted (`ProjectileManager.gd:24`), `Projectile.intended_target`, unreachable `_target != null` branches in Shambler INVESTIGATE/SEARCHING (`Shambler.gd:670-672, 700-703`), `NEIGHBORHOOD_LAYOUT` (~90 lines, `Main.gd:39-122`), `AITactician.set_hold_order`.
- Magic-number duplication: map bounds `50.0..6094.0` hardcoded in Shambler ×3 and Looter ×3; `MAP_TILES`/map size defined independently in 5 files; `32.0` tile size duplicated in SelectionManager instead of `IsoView.TILE_WORLD_PX`; faction literal `!= 2` in `NoiseField.gd:207`; Workshop hardcodes Engineer cost `50` ×3 while SettlementHub has named consts. Centralize in one constants file/autoload.
- `int()` truncation instead of `floori()` aliases negative coords into edge cells (`ZombieField.gd:153-154`, `DecayField.gd:68-69, 95-96`).
- `Engine.time_scale` (F2 dev 4×) survives match restart (`WinOverlay.gd:30-32`).
- Stale comments contradict code: projectile speed "2x" vs actual 4x (Looter/Rifleman/HeavyGunner); PerfProbe "t=0 baseline" never prints (`PerfProbe.gd:19-20`).
- Runtime `load()` instead of `preload` for corpse/Shambler scenes can hitch on first death (`Corpse.gd:50`, `Unit.gd:297`).
- Horde spawn jitter can place zombies off-map (`NoiseField.gd:286-288`); Scout emits loot noise even when 0 salvage is taken (`Scout.gd:190`); Wall destruction (noise 50) is the loudest event in the game while a collapsing HQ is silent (`Building.gd:77-79`).
- `Walker`/`Scout` never reset `current_command` after GATHER, blocking base-class cremation gating (`Walker.gd:120-126`); five unit subclasses don't early-return on `Command.CREMATE`.
- Hardcoded hotkeys (X/G) bypass InputMap; SelectionManager calls private HUD method; no ESC cancel for wall placement; drag state sticks on focus loss.
- Looter: double-kill salvage discarded by carry cap; `_last_kill_pos` records shooter, not victim (`Looter.gd:131-132`).
- TitleScreen `AICheck` unguarded node access (`TitleScreen.gd:24`); split-squad checkboxes wiped by any squad update (`SquadSidebar.gd:352`); Lootable field caches depend on `_ready` order (`Lootable.gd:70-71`).

## 5. Performance posture

One-time costs are fine (TownPlanner ~3-4M ops at load; all placement loops bounded). The steady-state concerns, in priority order:

1. **NoiseField pair loop** (H12) and **occluder cache mismatch** (H14) — the hot loop at 300 zombies.
2. **Scout/Walker per-frame group scans** (H13).
3. Per-wander-pick full-grid scans in ZombieField (`get_densest_cell_*` iterate 2304 cells; cache in the existing 1 Hz recompute).
4. Repeated `get_first_node_in_group` in Shambler hot paths (9+ call sites — cache in `_ready`); per-candidate building-group scans in wander scoring.
5. Per-projectile per-physics-frame allocations (`PhysicsRayQueryParameters2D.create` + excludes array, `Projectile.gd:133-141`); trail points maintained for styles that never render them.
6. Brawler/Engineer re-path `_nav.target_position` every physics frame while chasing (forces re-path; throttle like Looter's `RETARGET_INTERVAL`).
7. HUD polls and rewrites button text every frame (`HUD.gd:154-172`); Corpse `queue_redraw` every frame for a 16 px bar; wall-ghost validity recomputed per mouse-motion.
8. All units' engagement timers tick in lockstep (reset to the same constant) — periodic same-frame scan spikes; jitter the initial timer.
9. 225-zombie single-frame horde spawn (also a correctness issue, see Medium).

## 6. Design-doc & prototype-plan alignment

### Stat mismatches (design §7.x vs code; significant only)

| Item | Design | Code | Where |
|---|---|---|---|
| Shambler speed / melee | 1.5 t/s / 8 | 2.0 / 14 (commented as deliberate retune) | `Shambler.tscn`, `Shambler.gd:71` |
| Looter role | loud *gatherer* (loot noise 25) | **doesn't loot at all** — zombie bounty hunter, `clean_kills` | `Looter.gd` |
| Looter noise/shot | 8 | 20 | `Looter.gd:17` |
| Walker loot/trip | 70 | 25 | `Walker.gd:5` |
| Shaman speed | 2.3 | 1.875 | `Shaman.tscn` |
| Scout | DPS 5, silent gather (0) | no attack; unspecced energy system; gather noise 1.0 | `Scout.gd` |
| Build times | 18-60 s across the board | 6-13 s for most units | producers |
| Noise decay / thresholds | 5/s; 100/250/500/1000 | 10/s; 150/400/800/1600 | `NoiseField.gd:3,23-30` |
| Corpse return | 100% combat units, all factions | 30%, Military+Zombie only; Survivors never | `Rifleman.tscn`, `Unit.gd:291` |
| Runner/Brute zombie variants | specced §7.4 | absent — all hordes Shambler-only | — |

Verified matching: most unit HP/speed values, Hunter stats, HG noise rate (50/s effective), force-spawn (5 s / 25 / 4), decay accumulation/cap/multipliers (2× at 50+, 3× at 100+), cremation 4 s channel, corpse timer formula (doc-compliant `30 + HP/5`; the plan's flat 90 s was superseded).

### Spec deviations that matter

- **Noise architecture**: spec'd 16-tile accumulation grid; built as point-emitter list + a second unspecced `ZombieField` residue grid. Plus unspecced cooldowns, wave multipliers, occlusion, probabilistic hearing. Richer than spec — but undocumented, and the tier/cooldown interaction is buggy (H5).
- **Tribal zombie-immunity narrowed**: plan says the whole Tribal faction is invisible to aggro; code exempts *only Walkers* (`Shambler.gd:1301-1304`). Plan item 22's acceptance test fails for Hunter/Shaman. Tribal-aligned force-spawns also expire after an unspecced 30 s.
- **Decay**: only the Command Post is in `decay_emitter`; the plan says *every* active Military structure emits. Military expansion via Barracks is currently decay-free, weakening feel-check #3 (decay regret).
- **Enhanced returns diluted** (plan: "the soul of the game; do not skip it"): 30% base chance, Military-only, Looter magnum *always* clean-kills, veterans suppress another 10-18%. The "your dead Rifleman walks back" moment is now ~1-in-4. Meanwhile dead *zombies* recycle at 100% — backwards relative to the design's intent.
- **Military economic identity inverted**: the loot-noise-zombie tension (§5.2) has no implementation path since the Looter doesn't loot; the Looter is incentivized to *deplete* zombies and its kills don't even feed the corpse cycle.

### Prototype-plan checklist (items 1-46)

- **Done (22)**: camera, unit base, selection, nav movement, HUD, production queues, Rifleman, HG noise, Tribal camp/Walker/Lodge/Hunter/Ritual/Shaman force-spawn, faction picker, decay overlay+multipliers, cremation, two-faction map, win/defeat overlay.
- **Partial (12)**: Looter loop *replaced*, infested rates/intervals retuned, noise grid→emitters, horde thresholds retuned, corpse chance gutted, Tribal immunity narrowed, only-CP decay, no rally points, Barracks built from CP queue not Looter-placed.
- **Missing (the verdict apparatus)**: **item 38 hot-seat (no F1, no "hotseat" anywhere in the repo)**, item 39 match-start state (HQ + 2 workers + 1 combat + 300 salvage — currently HQ only, 200), items 44-46 (playtest notebook, top-3 feel issues, decision document).

### Scope drift (plan commitments vs repo)

| Plan said | Repo has |
|---|---|
| "No art passes — colored squares the whole way" | 907 asset files (896 are 8-direction animation frames for just Looter+Rifleman), full isometric rendering layer |
| One static 80×80 map | 192×192 procedural town (1,413-line TownPlanner) **plus** a second image-to-map pipeline |
| 2 factions, 6 units | 3 factions, 10 unit types — the entire Survivor faction is unplanned |
| 6 building types | 13 building scenes |
| Hot-seat *instead of* "a dumb AI" | The dumb AI was built; hot-seat wasn't |
| Not mentioned at all | Squad/command-tree system (1,100+ lines), veterancy/XP/clean-kills, projectile sim, ZombieField ecology, ~1,000 lines of zombie social behavior |

Well under a third of the ~6,800 gameplay script lines map to plan items. The Shambler social simulation alone exceeds the plan's entire Week-2 scope.

## 7. Recommended fix order

1. **C1** Brawler/Building `take_damage` signature (5-minute fix, crash).
2. **H7/H8/H9** Selection/squad UI crashes and re-entrancy — these hit every session.
3. **H5 + H6 + H14** Horde tier consumption, vision cap, occluder radius — these three silently break the noise/zombie loop the whole game is testing.
4. **H4 + H10** Introduce one ownership/hostility helper; apply in targeting, selection, HUD, projectiles, repair.
5. **H1** Engineer wall soft-lock; decide the walls-vs-navmesh policy.
6. **H2/H3/H11** AI stall, command spam, freed-HQ guard.
7. **H12/H13** The two hot loops (NoiseField range-check-first; throttle Scout/idle gatherers).
8. Medium batch: pop-cap enforcement in corpse rises + horde clamps, Shaman fixes, TownPlanner alley/seed/spawn-coordinate fixes.

## 7.5 Post-fix follow-up notes (added 2026-06-07, after all C/H items closed)

Observations from diff-verification of the fix batches — real but minor; fold into future batches when touching these files:

- **AITactician rally liveness gap:** if fewer than ATTACK_DISPATCH_GROUP_SIZE (4) units can ever stage (army capped by losses + dead economy), staged units wait at the rally indefinitely. Add a dispatch timeout (e.g., staged > 0 with no dispatch for 30s → send what you have). Related, accepted-as-is: pass 2 dispatches an engaged-at-rally unit (one move_to mid-fight at the dispatch moment) — chosen over leaving stragglers behind.
- **AI economic dead-end remains by design:** stall recovery (H2 fix) requires 50 salvage for a replacement Looter; an AI with zero Looters and <50 banked has no income path and quietly loses. Acceptable as a defeat state; revisit if AI gets a trickle income.
- **Engineer wall-resume (H1 fix) re-paths every tick** while out of range — same per-tick `_nav.target_position` pattern as the Medium Brawler/Engineer chase item. Throttle when that item gets fixed.
- **Subclass invariant (from H3's is_engaged accessor):** Unit subclasses that override _process without calling the engagement-timer logic silently break is_engaged() for the tactician. Documented here so the next unit class doesn't trip it.
- **NoiseField suppression print** (fixed earlier batch) and **unit_died faction int-vs-string** in MatchStats events remain open one-liners.
- **Lootables are no longer click-selectable** (H10 ownership gate side effect — they're NEUTRAL, not player-owned). Verify in play whether lootable inspection mattered; if so, allow selecting NEUTRAL buildings read-only.

## 8. The bigger question

The prototype plan exists to answer one question — *do Military and Tribal feel like different games, and is the noise/zombie/decay loop worth keeping?* — and the three things that answer it (hot-seat, undiluted enhanced returns, the Looter's loud-gathering identity) are respectively missing, gutted, and replaced. The systems that were built instead (squads, veterancy, town generation, sprite art) are Phase-1+ work per your own plan. Before more feature work, consider: restore the corpse-return rate for combat units, give the Looter back a loot loop (or consciously update the design doc to the bounty-hunter identity), implement item 39's match-start state, and either build hot-seat or accept the AI as the test vehicle and fix H2-H4 so it can actually fight. Then run the Week-6 verdict the plan calls for.

---

# FOLLOW-UP AUDIT — 2026-06-09 (determinism sweep)

*Scope: full re-sweep of scripts/ + autoloads/ against CLAUDE.md's six Determinism Rules, after the day's batches (CommandBus/replay/checksum harness, 2:1 projection migration, Tribal vertical slice, morale system). Method: pattern sweep (grep battery) + targeted hunk reads. Severity follows the 2026-06-07 scale. Numbering D1+ to avoid colliding with the original C/H/M/L items.*

## Executive summary

The new systems built this week (CommandBus, ReplayRecorder, SimChecksum, morale, Tribal slice, projection migration) are **clean** — they follow the rules they were built under. The violations concentrate in the **older substrate**, and they cluster into one theme: **sim state advancing on `_process(delta)` and wall-clock reads** — exactly the class of bug the replay harness will trip over first. The Tribal producers got fixed in the slice; their Military/Survivor siblings did not, so the codebase is now *inconsistently* deterministic. Worth closing the gap while the pattern is fresh.

## D-Critical (will break replay/lockstep correctness directly)

- **D1 — NoiseField advances sim state in `_process` AND uses wall-clock for the horde cooldown.** `NoiseField.gd:135` (emitter intensity decay + horde tier firing on render frames) and `NoiseField.gd:145,209` (`Time.get_ticks_msec()` gates the 30s horde cooldown). Double hit: (a) under `Engine.time_scale = 8` (AI-vs-AI lab), noise decays 8x faster per *sim* second than in normal play, so headless balance data does not represent real matches; (b) wall-clock cooldown means horde timing depends on machine speed — a guaranteed desync and a replay-divergence source. Fix: move decay/tier logic to `_physics_process`, replace wall-clock with `GameState.sim_seconds()`. **This is the single highest-priority determinism fix in the codebase.**
- **D2 — Corpse rise timer runs on `_process`.** `Corpse.gd:58-65`. The corpse economy is the design thesis, and its central timer advances on render frames (time_scale- and framerate-coupled). Move to `_physics_process`.
- **D3 — ZombieField density recompute + residue decay on `_process`.** `ZombieField.gd:81-89`. These are the zombie steering inputs — the core of §3.2. Move to `_physics_process` (the internal interval accumulators are already there; only the driver is wrong).
- **D4 — Unit cremation channel + XP accrual on `_process`.** `Unit.gd:226,243-246`. `_tick_cremation(delta)` (a sim channel) and `combat_time` accumulation (feeds XP/veterancy) advance on render frames. The facing/z-index/sprite-offset part of this function is correct render work — split the function: render stays in `_process`, cremation + engagement/XP move to `_physics_process`.

## D-High

- **D5 — Military/Survivor producer buildings still run production on `_process`.** `Barracks.gd:88`, `CommandPost.gd:92`, `Workshop.gd:78`, `Safehouse.gd:75`, `SettlementHub.gd:113`, `Greenhouse.gd:15`, `WaterCollection.gd:15`, `Lootable.gd:100`. The identical violation was fixed for TribalCamp/HuntingLodge/RitualSite in the Tribal slice — these eight files need the same one-line change (`_process` → `_physics_process`). Until then, Military/Survivor build times are wall-time while Tribal build times are sim-time: a real cross-faction balance skew at any non-1.0 time_scale.
- **D6 — Formation positions computed with transcendentals.** `SelectionManager.gd:201` (`cos/sin` in `_formation_position`). These results become nav targets = sim state (Rule #5). Fix: precomputed offset table (the ring layout is fixed — 6/12/18 slots) or integer-vector approximations. `Main.gd:414` has the same pattern but is the dev-only `--repro-hg-horde` path (Low). `Unit.gd:632` is in `_draw` — sanctioned render use.
- **D7 — AIController production countdown uses raw `_process` delta.** `AIController.gd:74-78`. Comment says wall-time is intentional, but production completion mutates sim state (spawns units). Under time_scale 8, AI production is 8x faster per sim-second than the player's. Should anchor on `GameState.sim_seconds()` like the strategist/tactician loops in the same file already do.
- **D8 — Bare RNG in remaining gameplay sites.** Sweep found 18 files; the high-value targets (everything new + Tribal producers + edge wanderer + Shambler init) were converted this week. Remaining notable: `Projectile.gd` (spread rolls), `CombatUnit.gd`, `Unit.gd` (corpse-chance rolls), `Lootable.gd`, `Barracks/CommandPost/Workshop/Safehouse/SettlementHub` spawn jitters, `NoiseField.gd` (horde spawn positions), `TownPlanner.gd` (map gen — replay-safe because replays snapshot the town, but cross-client live map gen would diverge), `Shambler.gd` hot path (~25 sites, documented as convert-when-CI-names-it in NETCODE.md). Convert opportunistically per CLAUDE.md's grandfathering rule; prioritize Projectile + Unit corpse rolls since they're combat-outcome-affecting. FIXED 2026-06-09 — full sweep complete (Shambler 26 hot-path sites, Unit corpse rolls, Projectile spread, all building spawn jitters); record-vs-record frontier moved tick 420 -> 2760; remaining divergence is move_and_slide physics (NETCODE.md irreducible #1).

## D-Medium

- **D9 — `GameState.spend` direct in all producer buildings + Engineer.** Known and deferred (AI doesn't use building actions today; it spawns directly from its own pool). Becomes load-bearing the day AI-run factions use `do_action`. Tracked in the Tribal slice plan; listed here for completeness.
- **D10 — Projectile hit resolution via `intersect_ray`.** `Projectile.gd:139,153`. Physics query deciding gameplay outcomes (Rule #3) — grandfathered, but projectile hits are exactly the kind of thing that diverges across machines. The steering-field migration plan should include a projectile-hit rework (deterministic swept-segment vs. unit positions).
- **D11 — Shambler vision via `intersect_shape`.** `Shambler.gd:1497-1499`. Grandfathered + already documented in NETCODE.md as an irreducible-until-steering-field item. No action now; listed so the audit is complete.
- **D12 — DecayField `_process`.** `DecayField.gd:57`. Mostly draw-cost work (viewport cull), but verify the decay *state* mutation isn't in the `_process` path before declaring it render-only. 10-minute check next time the file is touched.

## What's already clean (verified this sweep)

- **CommandBus / ReplayRecorder / SimChecksum** — no violations; SimChecksum's pre-sort kills iteration-order sensitivity by construction.
- **Tribal slice (Walker/Hunter/Shaman/TribalCamp/HuntingLodge/RitualSite)** — all five phases clean; the slice actually *removed* 7 pre-existing violations.
- **Projection migration** — render-only, confirmed by replay checksum reproduction at ticks 60+120.
- **Morale/personality system** — SimRng-rolled archetypes, physics-tick morale ticks.
- **MatchStats/PerfProbe/HUD/RTSCamera/SquadSidebar `_process` uses** — I/O, UI, camera; legitimately wall-time.
- **17 of the original audit's findings carry FIXED tags**; no regressions of those fixes found in this sweep.

## Recommended fix order

1. **D1** (NoiseField) — highest value; unblocks trustworthy balance-lab data AND removes the biggest replay divergence source.
2. **D2 + D3 + D4** (Corpse/ZombieField/Unit) — same pattern, one batch, ~4 files.
3. **D5** (eight producer buildings) — mechanical one-liners, one commit.
4. **D6 + D7** — small targeted fixes.
5. **D8** opportunistically; **D9-D12** when their systems are next touched.

Estimated: items 1-4 are one focused session. After them, re-run `tools/determinism_test.sh 42` — the replay should reproduce significantly deeper than the current tick-180 divergence.
