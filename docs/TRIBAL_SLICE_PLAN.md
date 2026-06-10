# Tribal Vertical Slice — Audit + Phased Plan

> **📸 SNAPSHOT (2026-06-09) — LARGELY EXECUTED; read as history, not as a to-do list.** The slice shipped: the determinism cleanups, the walkers-group exemption, the all-healthy-Tribal immunity, and the smoke test all landed. **One thing pivoted:** the Hunter's "constant clicking" signature described throughout this doc was **never implemented as designed** — playtesting showed clicking fed NoiseField and gathered ~50 zombies, so on 2026-06-10 it was replaced by the **passive defensive thrall escort** (≤4 zero-DPS bodyguards, no noise). The current Hunter design is **DESIGN_MASTER §7.2**; ignore every "clicking" reference below. Source of truth for anything here = DESIGN_MASTER + the code.*

*Plan-first deliverable, 2026-06-09. Built per request to audit existing Tribal code against DESIGN_MASTER §7.2 + §3.0 and surface a 5-phase plan + open design decisions for approval before execution.*

**Slice goal:** Tribal is playable as a faction for 20 minutes and feels distinctly asymmetric vs Military — NOT "quiet Military." Deliberately defers: Caller, Plague Spreader, Beastmaster, full doctrines, full blood/scent trail system, Marrow creep.

---

## 1. Audit — existing Tribal code vs design

| File | LOC | State | Reusable? | Issues |
|---|---|---|---|---|
| `scripts/TribalCamp.gd` | 149 | Works | **Mostly** | `_process(delta)` mutates production timer (**Rule #2**); `GameState.spend()` direct (not owner-aware → AI Tribal would steal player's salvage if it ever ran Tribal); `randf_range` bare for spawn jitter (**Rule #1**) |
| `scripts/Walker.gd` | 167 | Production-quality economy | **Yes** | Confirmed gather→deposit loop is owner-aware via `deposit_salvage()`; `get_nodes_in_group("lootable")` iteration picks min-distance (order-independent ✓); needs `walkers` group membership wired at `_ready` (the load-bearing exemption hinge — Shambler.gd line 1444 keys off `is_in_group("walkers")`) |
| `scripts/Hunter.gd` | 108 | On CombatUnit substrate | **Yes** | Inherits CombatUnit's morale/personality plumbing (need to verify by reading CombatUnit); `_should_skip_target` correctly excludes ZOMBIE faction (Tribal doesn't shoot zombies ✓); arrow projectile + kite + suppression cone all wired; **MISSING**: the design's "constant clicking" ambient noise that pulls zombies around the Hunter — current code only emits noise per-shot |
| `scripts/Shaman.gd` | 113 | Force-spawn works | **Yes** | Cost routes through `can_spend_salvage`/`spend_salvage` (owner-aware ✓); spawns 4 tribal-aligned Shamblers; population cap respected per-iteration ✓; **Issue**: `randf_range(-32, 32)` jitter on line 96 is bare RNG (**Rule #1**); force_spawn already routes through CommandBus from SelectionManager (we did that two batches ago) |
| `scripts/HuntingLodge.gd` | 88 | Produces Hunter | **Mostly** | Same three issues as TribalCamp: `_process(delta)` timer (**Rule #2**), `GameState.spend()` not owner-aware, `randf_range` bare (**Rule #1**) |
| `scripts/Shambler.gd` | ~1500 | Substrate ready | **Yes** | Already supports `walkers` group exemption (line 1444) and tribal-aligned ZOMBIE exemption (lines 727-732); extending to all-Tribal-while-healthy is **adding one more filter branch** in the existing perception logic — small targeted edit |
| `scripts/TitleScreen.gd` | ~50 | Tribal button works | **Yes** | Line 43: `TribalButton.pressed.connect(_on_tribal_pressed)` already wired; sets `player_faction = TRIBAL`; bypass-to-Main goes via the existing flow |
| `scripts/Main.gd` `_spawn_hq` | — | Routes by faction | **Yes** | Line 606: `TRIBAL → TC_SCENE.instantiate()` already in place |

**Substrate readiness:** CombatUnit + the morale/personality system (DESIGN_MASTER §5.1, landed last batch) + the counter-system seams (`damage_type`/`unit_size`/`armor` per NETCODE.md Decision #2) + SimRng + the zombie chassis (`is_tribal_aligned` field) are all present and used by Hunter today. CommandBus is in place; force_spawn already routes through it. The replay/checksum harness from earlier today doesn't gate any Tribal work.

**Headline finding:** Tribal is closer to playable than it looks. The hardest piece — the load-bearing "walkers exemption" in zombie perception — is already in. What's missing is (1) cleanup of three determinism violations that share the same shape across Camp/Lodge/Shaman, (2) extending the existing exemption to all-healthy-Tribal, (3) verifying the Hunter signature (clicking noise) is present, (4) end-to-end smoke test that the whole loop runs as a Tribal player.

---

## 2. Phased plan (each its own commit, each feel-testable)

### Phase 1 — Walker economy correct; producer determinism cleanup

**Goal:** Walker strolls through hordes untouched and the production line is sim-deterministic.

- Verify `Walker._ready()` adds itself to the `walkers` group; if not, add. This is the load-bearing line — without it, zombies will target Walkers and the "Walker wonder" feel is dead.
- Convert `TribalCamp._process(delta)` and `HuntingLodge._process(delta)` to `_physics_process(delta)` (CLAUDE.md Rule #2: sim state on physics tick, not wall-time `_process`).
- Convert TribalCamp's `GameState.spend(WALKER_COST)` → owner-aware (use the `can_spend_salvage`/`spend_salvage` pattern that Shaman already uses; HuntingLodge same).
- Convert `randf_range` bare calls in TribalCamp + HuntingLodge spawn-jitter sites to `SimRng.randf_range` (Rule #1).
- Confirm Walker's `_find_nearest_camp` returns the player's TribalCamp when picking Tribal (it already filters by owner group — `player_buildings` vs `ai_buildings`).

**Feel test:** Pick Tribal, see Walker spawn, click on infested house, watch it gather and return to camp. Drop a Shambler horde between the Walker and the building — Walker walks through them untouched. Salvage ticks up.

**Determinism: routed through SimRng. Reviewer subagent should clear this batch.**

### Phase 2 — Hunter onto the CombatUnit substrate (verified) + clicking signature

**Goal:** Hunter feels like a deliberate aimed silent stalker — distinct from Rifleman by silhouette (bow, organic palette) AND by behavior (low per-shot noise, but constant ambient clicking that pulls nearby zombies into a "living armor" cluster around him).

- Read `CombatUnit.gd` and confirm Hunter inherits morale + personality fields (rolled at spawn via SimRng per §5.1). If anything's missing — wire it on Hunter.
- Confirm counter-system seams exist on Hunter (`damage_type`, `unit_size`, `armor`) with neutral starting values per NETCODE.md Decision #2.
- Add the **ambient clicking noise**: a periodic NoiseBus emit at Hunter's position (every CLICK_INTERVAL seconds at CLICK_MAGNITUDE intensity, both as named constants). Tuning [OPEN] — see §3.
- The clicking goes on Hunter's `_physics_process` (sim tick) via an accumulator, NOT `_process(delta)`.
- Hunter's per-shot `NOISE_PER_SHOT = 1.0` stays — the Hunter is silent-fire but ambient-loud, which is the inverted signature vs Military Rifleman (loud fire, silent ambient).

**Feel test:** Spawn a Hunter near a Shambler cluster. Watch zombies drift toward him AND stay clustered around (the constant click pulls them, the no-per-shot-noise lets him fire without breaking the cluster). Now fire — arrows go out, the cluster stays. The Hunter is firing from inside his own bodyguard.

**Determinism: clicking timer is sim-tick-driven; NoiseBus emit is already deterministic.**

### Phase 3 — Conditional immunity v1 ("blood breaks the mask")

**Goal:** A healthy Tribal Hunter walks among the dead; a wounded Hunter gets eaten. The defining Tribal tension ("pull your wounded out or they get eaten") shows up at the feel-test level.

- In Shambler's existing perception filter (the same place that handles `walkers` exemption + tribal-aligned exemption — Shambler.gd lines ~1440), add one more branch: also exempt any unit where `faction == TRIBAL` AND `current_hp >= max_hp * TRIBAL_IMMUNITY_HP_THRESHOLD`. Threshold value [OPEN] — see §3.
- Walker (in `walkers` group) keeps **unconditional** immunity per its design role as the bone-painted scavenger. Decision below.
- Optional visual cue: modulate the wounded Tribal sprite slightly (a faint red tint, or a sustained particle puff) so the player can read "they're exposed now" at a glance. Scope-flexible — drop if it adds delay.

**Feel test:** Send a healthy Hunter into a horde — untouched. Take him down to half HP via Military fire — now zombies turn on him and pile in. Pull him back to a Plague Spreader (or wait for in-Tribal-territory regen if that lands) — once topped up, the mask returns. The "manage your bleeding line" mechanic shows up.

**Determinism: no RNG involved; deterministic by construction.**

### Phase 4 — Shaman force-spawn cleanup + balance

**Goal:** Shaman is fully wired AND clean.

- Convert Shaman's `randf_range(-32, 32)` jitter (line 96) to `SimRng.randf_range` (Rule #1).
- Verify CommandBus dispatches the force_spawn correctly when player clicks (already routed — we did this two batches ago).
- Tune cost / spawn count / channel time for the lab. Current placeholders: `FORCE_SPAWN_COST = 25`, `FORCE_SPAWN_COUNT = 4`, `FORCE_SPAWN_CHANNEL_TIME = 5.0`. Values [OPEN] — see §3.

**Feel test:** Build Shaman from Ritual Site, walk it to an infested commercial building, channel, watch 4 tribal-aligned Shamblers erupt and pour toward enemy territory. They're tribally aligned for the 30-sec window per Shambler.gd existing behavior — long enough to do meaningful damage, short enough to keep horde aggro honest.

**Determinism: SimRng conversion makes the spawn jitter reproducible.**

### Phase 5 — Playable end-to-end

**Goal:** Title-screen Tribal pick → 20-minute self-directed Tribal game.

- Title screen: already wired (Phase 0 verification only).
- Main spawn flow: TribalCamp spawns at player corner; `_spawn_hq` faction-routing already exists.
- Confirm starting resources allow a Walker queue + Hunting Lodge + Hunter + Ritual Site + Shaman path within a reasonable opening (~3-5 sim min).
- Run the determinism harness on a recorded Tribal-vs-Military AI-vs-AI match (when AI controllers support Tribal). For the slice, Tribal is **player-only**; the AI opponent is Military per the existing AIController.

**Feel test:** Start the game, pick Tribal, play 20 minutes against a Military AI. Distinct game? Pull-your-wounded tension? Force-spawn-as-pressure-release? Hunter feels like ambush rather than line infantry? Asymmetric thesis intact?

**Determinism: each prior phase has its own commit + reviewer pass; this phase is integration + telemetry.**

---

## 3. Open design decisions — need answers before building

### (a) Ritual mats — true second resource or flavored salvage? *[DESIGN_MASTER §7.2 explicitly OPEN]*

The full design calls for ritual mats as a separate resource — gathered from infested buildings and dead Brutes, spent on Tribal units. A true second resource means:

- TribalCamp tracks `ritual_mats` separately from `salvage`.
- Walker's `_carrying` splits into salvage vs mats based on source.
- Hunter / Shaman / future units cost mats, not salvage.
- HUD shows two numbers.
- Affects every cost-check in the Tribal path.

Vs. **flavored salvage**: one pool, HUD just labels it "Ritual Mats" when faction == TRIBAL. Same numbers, different word.

**My recommendation: flavored salvage for the slice.** The asymmetric thesis we're testing is "Tribal feels different from Military," which is delivered by the Walker wonder + Hunter clicking + force-spawn pressure + blood-breaks-the-mask. The second-resource layer is a macro-economy feature that belongs after the unit-level asymmetry is proven. Lab can test "does Tribal feel different" without it; can't test "does the mats-economy curve work" without it. One question at a time.

**Your call:** flavored salvage now (faster, lab-focused) / true second resource (slower, design-complete)?

### (b) Shaman force-spawn tuning *[placeholder values]*

Current placeholders: 25 salvage cost, 4 zombies per ritual, 5s channel time.

- **Cost**: 25 is cheap (TribalCamp Walker is 50). Too cheap → spam force-spawn. Recommend 40-60 for the lab.
- **Spawn count**: 4 is iconic ("a small horde from the floorboards"). Could go to 5-6 for stronger pressure. Recommend keep 4 — readable, deterministic.
- **Channel time**: 5s is short for a "ritual." A 7-10s channel makes the Shaman a deliberate commit — and a unit the enemy can race to interrupt. Recommend 7s.

**Your call: cost / count / channel?** Default I'll use if you don't specify: `40 / 4 / 7`.

### (c) HP threshold for the conditional immunity *[design says "wounded = exposed"]*

The "wounded" line is a knob:

- **50%** — heavy wound. Any sustained engagement exposes you. Most dramatic; aggressive players punished hard.
- **67%** — moderate. Casual engagement still safe; a real fight peels the mask.
- **75%** — sensitive. One sustained burst exposes you. Most punitive.

**My recommendation: 50%.** Cleanest single number; matches the "pull your wounded out OR they get eaten" tension hardest; rewards heal-management rather than panic-retreat-on-first-shot. The lab can move it.

### (d) Walker — permanently immune, or also exposed when wounded?

Design §7.2 doesn't explicitly except Walkers from the "blood breaks the mask" rule. The current code keeps Walker permanently immune (via the `walkers` group exemption in Shambler).

- **Permanently immune (current behavior)**: Walker is the iconic "untouched scavenger"; preserves the "Walker wonder" feel; gives Tribal a hard guarantee that the economy worker never dies to a horde.
- **Conditionally immune (apply mask rule)**: Walker also exposed when wounded; more design-coherent with "blood breaks the mask"; but vulnerable economy worker = much harder Tribal opening.

**My recommendation: keep Walker permanently immune.** The design language ("walks among the dead untouched, always") reads as Walker-specific in §7.2 even though the rule is stated generally. And the economic loop wants the Walker to be reliable. Combat Tribal can bleed; Walker can't.

### (e) Hunter clicking noise tuning *[placeholder values]*

The constant ambient noise that pulls zombies into a cluster around the Hunter. Tuning candidates:

- **Interval**: 1.5 - 3 sec between emits. Faster = stronger pull, more sim cost.
- **Magnitude**: should be LOUDER than per-shot (1.0) since per-shot is a *deliberate* low-noise event and the clicking is *passive* identity. Recommend 2.0-3.5.

**My recommendation: 2.0s interval, 3.0 magnitude.** Loud enough to anchor a cluster within ~2 tiles; intervals frequent enough that zombies don't drift away between clicks. Lab tunes.

### (f) Anything else the audit revealed

- **Hunter morale/personality + counter-seams**: I assumed inherited from CombatUnit. Phase 2 starts by verifying — if the inheritance isn't complete, the wiring lands in that phase. No design call needed; just acknowledging the unknown.
- **AI doesn't run Tribal**: known. The slice is **player-only Tribal vs Military AI**. AI Tribal extension is a future batch (see CLAUDE.md `project_deferred_systems`).
- **The visual cue for "wounded Tribal exposed"** (Phase 3 optional): nice-to-have but **drop it from the slice if it adds work**. The mechanic tells the story; the visual is decoration.

---

## 4. Determinism notes for the whole slice

- Every new RNG call routes through SimRng.
- Every command (force_spawn, build, move) goes through CommandBus.
- No new `_process(delta)` mutating sim state; production timers move to `_physics_process` or sim-tick accumulators.
- Iteration over `get_nodes_in_group()` (lootable, walker, tribal_camp): all uses I audited are order-independent (min-distance picks, group membership tests). No changes needed.
- Determinism reviewer subagent invoked after each phase commit.
- Parse-check Stop hook runs at every turn-end.

The slice does NOT introduce any new transcendental usage, physics queries for gameplay decisions, or sim/render leaks.

---

## 5. What this slice does NOT do

Explicitly deferred (per request) — listing here so future-me doesn't lose track:

- **Caller, Plague Spreader, Beastmaster** — not in this slice.
- **Doctrines** (Bone-carrier/Seeder, Still-path/Deep-click, etc.) — not in this slice.
- **The Marrow creep system** (§3.0) — not in this slice; Tribal's territory-claim mechanic.
- **The full blood/scent trail system** — not in this slice; Phase 3's HP-threshold is the v1 proxy that delivers the *feel* of the mechanic without the trail infrastructure.
- **AI playing Tribal** — not in this slice; AIController stays Military-only.
- **The Congealed** (Tribal endgame fused-zombie) — not in this slice.
- **Ritual mats as a true second resource** — pending (a) above; default is flavored salvage in the slice.

---

## What I need from you

1. **Answer the design decisions** in §3 (a)/(b)/(c)/(d)/(e). If you skip (b)/(c)/(e), I use the recommended defaults. (a) and (d) need explicit answers.
2. **Approval** — "Approved, proceed" and I start Phase 1.

I stop here per the plan-first contract. No gameplay code has been touched.
