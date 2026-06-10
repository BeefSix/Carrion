# AI Opponent Overhaul — Audit + Phased Plan (Track A)

*Plan-first deliverable, 2026-06-09 (overnight session). **No Track-A gameplay code has been
written** — this plan awaits Matt's approval per the Architect contract. Track C
(zombie variants + Medic) proceeds in parallel on the established pattern, as authorized.*

**Mandate:** the game has no real opponent. In a competitive RTS the opponent IS the
content — the zombies are the weather. Make the AI a competent, pressuring sparring
partner that can pilot BOTH factions. Target is "worthy sparring partner," not
world-class: the real opponent is human PvP later; the AI is the solo/test/campaign
stand-in. No rabbit holes.

**Lab precondition confirmed:** D1 (NoiseField wall-clock→sim-time) and D7 (AI
production on the physics tick + sim-time strategist anchors) are committed and the
record-vs-record CI reproduces to tick 360+ at `time_scale 8`. The balance lab's
clock is honest; measurements are valid.

---

## 1. Audit — what the AI is today

Three files, clean composition (Controller owns Strategist + Tactician), all evaluated
on sim-time anchors (post-D7). It is a **single hardcoded Military build order with a
two-trigger posture loop**:

| Capability | State today | Gap vs "competent" |
|---|---|---|
| Economy | 2 Looters, fixed; H2 stall-recovery floor of 1 | Never grows. No expansion, no salvage-rate awareness. A dead Looter is replaced; a third is never built. |
| Production | 7-step BUILD_ORDER → infinite Rifleman sustain | No Heavy Gunners (scene is preloaded but **no build-order row ever uses it**), no Workshop/tech, no composition logic. |
| Attack | Army ≥ 6 → rally → group-dispatch at enemy HQ | Good bones (trickle/stall fixed). But one target forever (enemy HQ), no re-evaluation en route, no retarget if the army walks past a killable expansion. |
| Defense | **None.** | Nothing reacts to its base being attacked. RETREAT triggers only on army losses, not on base damage. You can deconstruct its base while its army walks across the map. |
| Harassment | **None.** | Player never feels economy pressure. |
| Faction identity | Military-only; CP_SCENE hardcoded in `_spawn_hq`; Looter/Rifleman/HG scenes hardcoded | Cannot pilot Tribal at all. No noise-economy play, no suppression awareness even for Military. |
| Difficulty | N/A | No knobs beyond `--dispatch-group-size`. |

**Substrate readiness:** CommandBus routing is in (`_issue_if_changed` →
`CommandBus.issue`), telemetry snapshots exist (`ai_phase`, `ai_posture_changed`,
`ai_attack_ordered`, `ai_unit_dispatched`), owner-aware salvage is in
(`spend_for_production`), H11 HQ-death guards are in. The overhaul is an *extension*,
not a rewrite — the composition shape survives.

**Tribal blockers found by the audit (will be fixed in Phase A4):**
- `AIController._spawn_hq` hardcodes `CP_SCENE` (CommandPost).
- TribalCamp/HuntingLodge production spends via `GameState` player pool in places —
  the Tribal slice made player-side owner-aware; AI-side needs the same
  `owner_controller` routing the Military buildings already have.
- AITactician's rally/dispatch is faction-agnostic (good) but Tribal wants a different
  posture grammar (Stalk/Strike/Withdraw ≈ harass-first, not mass-and-commit).

---

## 2. Architecture — data-driven faction profiles, goal-stack strategist

Keep Controller/Strategist/Tactician. Two structural changes:

**(1) FactionProfile (a const Dictionary per faction, in a new
`scripts/ai/AIProfiles.gd`):** build order rows, sustain composition (weighted mix,
e.g. Military `{rifleman: 3, heavy_gunner: 1}` — weights consumed round-robin, NOT
random — deterministic), economy targets (worker count by sim-minute), attack
threshold, harass squad size, defend radius. The strategist reads the profile; zero
faction `if`s in the logic. **Difficulty later = a profile multiplier set, not new
code** (see Decision A below).

**(2) Goal-stack evaluation** replacing the linear build order. Each strategic tick,
the first unmet goal wins (strict priority — deterministic, no scoring floats):
1. **SURVIVE** — base under attack → defend (Phase A2).
2. **ECONOMY FLOOR** — workers below profile floor → build worker (exists, H2).
3. **ECONOMY GROWTH** — below worker target for current sim-minute → build worker.
4. **PRODUCTION/TECH** — profile build-order rows (barracks, lodge, ritual site...).
5. **ARMY** — sustain composition until attack threshold.
6. **PRESSURE** — threshold met → attack posture; harass timer → harass squad.

The existing BUILD/ATTACK/RETREAT posture machine survives as the *army* layer
underneath; goals decide what to spend, posture decides where the army stands.

---

## 3. Phases (each its own commit + CI + lab measurement)

### A1 — Strategist generalization (no behavior change)
Extract the hardcoded BUILD_ORDER/sustain/thresholds into the Military
FactionProfile; goal-stack skeleton with goals 2/4/5 only (= exactly today's
behavior). **Regression check: lab AI-vs-AI before/after shows the same build
timeline** (`ai_phase` telemetry diff). This is the "make the change easy" commit.

### A2 — Defense (the worst gap)
Buildings already know when they're damaged (`take_damage`). Wire: building under
attack → controller flag with the attacker's position → SURVIVE goal preempts →
tactician gets a DEFEND order (rally at the damaged building, engage, return to prior
posture when no base damage for DEFEND_COOLDOWN sim-sec). Measured: lab scenario
"send 4 units at the AI base while its army is away" → army comes home.

### A3 — Economy growth + composition + Heavy Gunners
Worker target curve (e.g. Military 2→4 Looters by minute 6 — profile data), sustain
mix adds Heavy Gunners at the profile ratio, work-anchor staking near infested
buildings (Military identity: farm the spawns its own noise feeds). Measured: salvage
curve slope in MatchStats vs today's flatline.

### A4 — Tribal AI (the unlock for the lab matchup)
- `_spawn_hq` routes by `faction` (CP vs TribalCamp) — same pattern Main uses.
- AI-side owner-aware production for TribalCamp/HuntingLodge/RitualSite.
- Tribal FactionProfile: Walkers → Hunting Lodge → Hunters → Ritual Site → Shaman;
  sustain mix Hunter-heavy.
- **Shaman force-spawn as an AI tactic:** strategist goal — when a Shaman exists and
  an infested building sits within profile range of the *enemy-facing* half of the
  map, send the Shaman to channel there (routes through the existing CommandBus
  `force_spawn`). This is Tribal's "zombies as a weapon" identity in AI hands.
- Hunter thralls accrue automatically (passive recruiting) — free identity.
- Tactician: Tribal profile uses smaller dispatch groups + earlier attacks
  (Strike/Withdraw flavor) — profile numbers, no new code paths.
Measured: **Military-vs-Tribal AI-vs-AI runs complete with winners** (no stalemate),
both HQs see attacks, Tribal telemetry shows force-spawns near enemy territory.

### A5 — Harassment + map contest
HARASS goal: every HARASS_INTERVAL sim-sec once army ≥ profile floor, peel the
profile's harass squad size (2-3) and send at the enemy's *economy* (nearest enemy
worker cluster / Lootable being worked, read via groups with stable min-distance
pick). Returns home on losses. This is the "player feels pressure" phase — feel-test
gated, with a lab proxy (enemy worker kills > 0 in AI-vs-AI telemetry).

### A6 — Measurement pass + tuning
Batch lab runs (5-10 seeds × Military-vs-Tribal both ways + mirror matches):
win-rate split, match length distribution, non-stalemate rate, salvage curves,
`ai_attack_ordered` cadence. Tune profile numbers only. Deliverable: a short
`docs/AI_LAB_REPORT.md` with the numbers, and Matt feel-tests "does it pressure me?"

---

## 4. Decisions for Matt

**(A) Competence bar + difficulty setting scope.**
My recommendation: tune the default to **"beats a first-time player, loses to a
focused one"** (pressures constantly, telegraphs honestly, never cheats resources).
Difficulty *settings* are **out of scope now** — but A1's FactionProfile structure
means a later Easy/Hard is literally a multiplier table (slower timers / bigger
armies), no new systems. Ship one good default; add the table when campaign work
starts. **Your call: agree, or want selectable difficulty in this batch?**

**(B) Harass aggression ceiling.** Harassment is what makes an AI *felt*, but too
much reads as bullying on a first playthrough. Recommend: first harass no earlier
than sim-minute 4, squad of 2, interval 90s (all profile data, lab-tunable).
**Default used if unanswered.**

**(C) AI Tribal force-spawn target policy.** Nearest infested building to the
*enemy HQ* (most aggressive, most readable) vs nearest to the *front line* (army
centroid midpoint — smarter, fuzzier). Recommend **nearest-to-enemy-HQ** for v1:
deterministic, dramatic, and it teaches the player what force-spawn does.
**Default used if unanswered.**

---

## 5. Determinism notes

All new decision logic on the strategic/tactical sim-time anchors (existing pattern);
strict-priority goal stack (no float scoring); profile mixes consumed round-robin
(no RNG); target picks are min-distance with first-seen tie-break (documented,
spawn-ordinal upgrade later); everything routes through CommandBus (already true).
Determinism reviewer + record-vs-record CI after every phase. No transcendentals,
no physics queries, no render reads.

---

*I stop here on Track A per the plan-first contract. "Approved" (with or without
decision answers — defaults listed) starts Phase A1.*
