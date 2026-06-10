# The Caller + Harvest-the-Dead — Audit + Plan (Track B)

*Plan-first deliverable, 2026-06-09 (overnight session). **No Caller code has been
written** — awaits Matt's approval. The harvest design is included here because the
two share the "Tribal works the dead" identity and one decision (ritual mats).*

**Mandate:** Tribal's "symbiosis with the dead" is under-built. Immunity removed the
downside but the upside — zombies as instrument — barely exists. A healthy Tribal
player should be constantly herding, commanding, and harvesting the dead. The Caller
is the army-scale zombie-commander (DESIGN_MASTER §7.2: Aztec death whistle, the
anchor and the stated faction weakness); harvest gives Walkers an economic
relationship with remains.

**The control ladder (distinctness contract):**
| Unit | Scale | Ownership | Verb |
|---|---|---|---|
| Hunter | personal (4) | owned thralls, defensive only | *wear* the dead |
| **Caller** | **army (area)** | **unowned influence — wild zombies stay wild** | ***aim* the dead** |
| Beastmaster (future, likely Herd-caller doctrine) | pack (named few) | owned, offensive | *keep* the dead |

The Caller must never own zombies — the moment he does, he's a fat Hunter. His whole
kit is influence on *wild* behavior. Caller dies → influence expires → existing
revert rule (§7.2) applies for free because nothing was ever owned.

---

## 1. Control model — the decision

### Option 1 — HERD (the whistle-anchor) ★ recommended v1
The Caller plants a **whistle-point**: a strong attractor at a target position within
CALLER_RANGE. Wild zombies in CALLER_INFLUENCE_RADIUS of the Caller drift toward it
(same direct-attraction path as the damaged-zombie groan — NOT NoiseField, so no
horde-spawn triggers, same lesson as the Hunter redesign). The whistle sustains while
the Caller channels (he's stationary + audible + vulnerable = the faction weakness,
mechanically); stops when he stops, dies, or retargets.
- *Why it wins:* purest "the dead are weather you steer." Indirect — you herd a mass
  toward a base/army/chokepoint and the zombies' own behavior (proximity sense, CHASE)
  does the killing. Maximum distinctness from Hunter (no ownership, no defense) and
  Beastmaster (no units). Most thesis-coherent counterplay: the enemy can out-noise
  your whistle (Military gunfire still attracts), kill the stationary Caller
  (Bolter/Longbolt decapitation per §7.3), or just not be where the herd arrives.
- *Doctrine runway:* War-caller = louder/farther/faster herding toward fights;
  Herd-caller = split/park/screen verbs. Both are extensions of the anchor, not
  rewrites.

### Option 2 — MARK (the death-call)
Caller marks one enemy unit/building; wild zombies within radius converge on the mark
and attack it for MARK_DURATION. RTS-legible ("focus-fire the horde"), but it skips
the herding fantasy — it's a targeted nuke with extra steps, and it overlaps the
future War-caller doctrine. Better as the *doctrine*, not the base kit.

### Option 3 — BIND (mega-thrall cluster)
Caller owns 12–20 thralls, Hunter-style but offensive. Most direct power, least
distinct (a bigger Hunter), heaviest determinism surface (20 owned units pathing),
and it collides with the Shaman-supply [PROPOSED] system. Reject for v1.

**Recommendation: Option 1 (HERD), with MARK reserved for the War-caller doctrine.**

### Sub-decision: delivery mechanism — direct attraction vs steering field
DESIGN_MASTER §3.2 says all zombie influences belong in ONE signed-weight field
system, and the Caller is the first unit whose entire kit is a field emitter.
- **(i) Quick path:** reuse the groan-pattern direct attraction (zombies in radius
  get a drift target). Ships this week. Risk: one more bespoke influence to migrate
  later — exactly what §3.2 warns about.
- **(ii) Field path:** build SteeringField v0 now (coarse grid, attractor list with
  signed weights, Shambler wander samples it) and make the whistle its first emitter;
  migrate groan + homeward bias opportunistically after.
**Recommendation: (ii) — minimal field now.** The Caller is the natural forcing
function for §3.2, the field is also the determinism fix for the zombie layer (the
CI's current tick-420 frontier is zombie wander RNG + physics — field sampling is
the architecture that retires it), and "do not build bespoke per-unit behaviors" is
already canon. Scope guard: v0 = ONE grid, attractor/repulsor list, sampled as a bias
on wander direction only (CHASE/ATTACK unchanged). If it balloons, fall back to (i)
with a field-shaped API.

---

## 2. Caller v1 kit (placeholder numbers, lab-tunable)

- Produced at Ritual Site (Shaman's building — they're the priest pair).
  CALLER_COST ~90, slow build.
- **Whistle (the one verb):** target a point ≤ CALLER_WHISTLE_RANGE_PX (~14 tiles);
  Caller channels, stationary; wild zombies within CALLER_INFLUENCE_RADIUS_PX
  (~8 tiles) of the *Caller* gain a strong drift toward the point. Influence follows
  field rules: it's a bias, distractible by louder noise (per §3.4's grammar —
  a bias, not a script).
- Whistle emits **zero NoiseField noise** in v1 (same anti-horde-spawn rationale as
  thralls; the audible-whistle-as-liability layer can come back deliberately as a
  tuned NoiseBus emission once hordes are wanted — flag, don't default).
- No attack. Fragile. The army-scale anchor and the decapitation target.
- Caller dies / stops channeling → attractor expires within ~1s → herd resumes wild
  behavior wherever it stands (no revert bookkeeping needed — nothing was owned).

---

## 3. Harvest the dead (Walker ↔ remains economy)

Today zombie deaths leave nothing harvestable; Tribal's economy ignores the
ecosystem entirely. Proposal:
- Zombie deaths leave **Remains** (reuse/extend Corpse.gd with a `harvestable` state
  for zombie corpses — they're already on the ground; rise-vs-harvest race is free
  drama and matches §4's corpse-race design).
- Walker gains a harvest interaction: channel HARVEST_TIME_S (~3s) at Remains →
  +HARVEST_YIELD (~8) salvage/mats, consumes the corpse (denies the rise — Tribal's
  quiet corpse verb, mirroring Looter shoot-to-loot loud / Chemist acid silent).
- **Brute remains** (Track C adds Brutes) yield BRUTE_HARVEST_YIELD (~40) — the §3.3
  "dead Brutes are a Tribal resource" line made real. [PROPOSED] wild-Brutes-ignore-
  the-mask pricing layer stays deferred.
- Walker AI: harvest only within a leash of its camp/anchor by default (no map-wide
  corpse chasing — the Looter leash lesson).

**Ritual mats (decision d):** keep **flavored salvage** (per the approved slice
default). Harvest yields make Tribal's *income sources* asymmetric already; promoting
mats to a true second resource is a macro overhaul that should wait until the Caller
+ harvest loop proves fun. Revisit at the Marrow/creep batch.

---

## 4. Phases

- **B1 — SteeringField v0** (if sub-decision = field path): grid + emitter list +
  wander-bias sampling; groan stays as-is; CI before/after (this *should* shrink
  zombie nondeterminism, not grow it).
- **B2 — Caller unit + whistle-anchor** on the field; Ritual Site production;
  CommandBus `whistle` command kind; selection UI hookup.
- **B3 — Harvest:** Remains state on zombie corpses + Walker harvest verb +
  CommandBus `harvest`; telemetry (`harvest` events).
- **B4 — Lab + feel-test:** herd a 20-zombie cluster into the Military AI's base;
  Walker harvests the aftermath; kill the Caller mid-herd and watch it dissolve.

Each phase: own commit, determinism reviewer, record-vs-record CI.

## 5. Decisions for Matt
1. **Control model** — HERD recommended (MARK→doctrine, BIND rejected). 
2. **Delivery** — SteeringField v0 now (recommended) vs quick direct-attraction.
3. **Whistle audibility** — silent v1 (recommended) vs NoiseBus-audible from day one.
4. **Ritual mats** — stay flavored salvage (recommended).

*Stopping here on Track B per the plan-first contract.*
