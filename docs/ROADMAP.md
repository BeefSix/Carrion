# THE LONG WAKE — Working Roadmap

*Agreed 2026-06-10 (Matt + advisor + builder). This is the SEQUENCE document — what
gets built in what order and why the order is load-bearing. Design truth stays in
DESIGN_MASTER.md; this file just keeps the phases from drifting. Update it when a
phase closes or the ordering is deliberately changed.*

## The thesis test
The game is good when three things are simultaneously true:
1. The **horde is genuinely threatening** and readable (walking into a crowd is a mistake).
2. The **opponent pressures you** (decisions matter because someone punishes the slow ones).
3. The **three factions answer the horde differently** (asymmetry is the pitch).
Everything else — doctrines, campaign, endgame units, netcode — is downstream of these.

## Phase order (each gated on a feel-test exit bar)

### Phase 1 — The Opponent (Track A) — ✅ CODE COMPLETE 2026-06-10 (feel-test pending Matt)
A1 profiles+goal-stack, A2 defense, A3 economy growth+composition, A4 Tribal AI,
A5 harassment, A6 lab report (docs/AI_LAB_REPORT.md — PROVISIONAL: Tribal 6-0-4
cross-faction, Military mirrors stalemate, corner asymmetry measured; A6b
re-tune budgeted after Phase 3).
**Exit bar:** Matt loses a game he was trying to win and immediately wants a rematch.
**Why first (load-bearing, not preference):** Phase 2's exit bar is "herd 20 zombies
into the Military base" — that feel-test is meaningless without a Military base that
fights back. The field's whole payoff is aiming the horde *at someone*. Opponent-first
cannot be flipped.
**Caveat:** A6's tuning numbers are provisional — tuned against a world where zombies
are still weather. A6b re-tune is budgeted after Phase 3 (see plan doc).

### Phase 2 — The Field + The Caller + Harvest (Track B) — ✅ CODE COMPLETE 2026-06-10 (feel-test pending Matt)
B1 SteeringField v0, B2 Caller whistle (silent v1), B3 harvest-the-dead
(19 harvests in the B4 sanity match), B4 TT lab sanity green.
**Exit bar:** herd a 20-zombie cluster into the Military AI's base, harvest the
aftermath with Walkers, and it felt like *conducting*, not micromanaging.
**Also closes:** the last determinism frontier (move_and_slide → field sampling) and
Tribal's missing "dead as instrument" upside.

### Phase 3 — The Threat Pass
**Exit bar:** walking a unit into a crowd reliably feels like a mistake; THEN the
§5.1 reaction/panic behaviors switch on (dependency order is canon: threat first —
units can't meaningfully panic at a harmless shuffle).
**Includes:** A6b AI re-tune (the hazard topology changed under the AI's feet —
expect win-rate shifts; that's the world changing, not a regression).

### Phase 3.5 — The Map Pass (runs alongside Phase 3/4 — DO NOT let this slide)
**Why it exists (advisor, 2026-06-10):** "zombies are the terrain" is half a map
statement. The field makes the horde a dynamic hazard, but *where it pools, which
lanes stay quiet, where infested clusters sit relative to expansions* is static
terrain design — that's what turns zombies-as-terrain from a unit mechanic into a
strategic one, and it's load-bearing for the competitive three-way pitch.
**Shape of the work:** NOT hand-authored maps first. The map is TownPlanner
procedural generation, so the pass starts as **hazard-topology parameterization**
(infested-cluster placement relative to spawns/expansions, lane widths, quiet
corridors, Brute wander basins) + **curated seeds** measured in the lab. Authored
competitive maps come after the generator proves which topologies create decisions.
DESIGN_MASTER §6.1 already names maps as a primary balance lever — this is its phase.
**Correctly deferred until now:** you can't design maps around a horde that doesn't
flow yet.

### Phase 4 — Survivors
**Exit bar:** the actual three-way game exists; first external feel-testers (2-3
trusted players) see it HERE, not before — first impressions are spent once.
The most design-novel faction: garrisons, civilians, broadcast economy, the Bus.

### Later, deliberately (not now, on purpose)
- **Doctrines, Marrow creep, Congealed, Humvee/Bus endgame, campaign** — after the
  thesis triangle is excellent.
- **Netcode LAST — hold this line hardest.** The discipline (determinism rules,
  harness, command bus) is already paid for; that was the expensive part. The wire
  is cheap later and murderous now: lockstep turns every iteration into a
  synchronized-across-clients problem, and iteration speed is the entire asset of a
  solo dev. Do not build it until the sim is fun.

## Standing process
- Weekly protected 20-minute feel-test session; Matt's verbal "what felt wrong"
  drives the next batch (the clicking→thrall redesign is the model).
- Every gameplay batch: own commit, determinism review, record-vs-record CI.
- Open design rulings get made when they block, biggest looming one: **does loudness
  leak through fog?** (§9 #1) — shapes Listening Post, Caller whistle audibility,
  Survivor broadcasts. Next in line after the Caller.
