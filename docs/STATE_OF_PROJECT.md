# THE LONG WAKE — State of the Project

*Snapshot 2026-06-10, written for Matt. This is the WHERE-WE-ARE document — a
corrected, complete version of the state summary reviewed earlier this week.
Sequence lives in ROADMAP.md; design truth in DESIGN_MASTER.md. Update this
when a phase closes or a blind spot below gets a ruling.*

## One paragraph

The prototype has all three pillars of the thesis test in code: a real
opponent (data-driven AI with goal stack, defense, economy, harassment, for
both Military and Tribal), a real field (SteeringField + Caller herding +
Walker harvesting), and faction asymmetry in units/noise/economy. The art
substrate is unified (gold pro-48 sprite family across 11 unit types), three
authored maps exist alongside the procedural town, SC-style worker
construction and a professional console HUD shipped. What's pending is FEEL
verification — every system above is code-complete and lab-tested but not yet
play-confirmed by a human — plus the blind spots listed at the bottom.

## What is DONE (code-complete, lab-verified)

### Track A — The Opponent (Phase 1)
- **AIProfiles.gd**: data-driven faction profiles (build order, sustain
  ratios, worker targets, attack/harass/forcespawn timings). Difficulty later
  = more data rows, no code.
- **Goal stack** (AIStrategist): SURVIVE → ECON FLOOR → ECON GROWTH →
  PRODUCTION → ARMY, with affordability fall-through (no head-of-line
  blocking) and a DEFEND posture triggered by base damage.
- **Tribal AI**: full profile (TribalCamp HQ, lodge/ritual tech, shaman
  force-spawns at the nearest infested-to-enemy-HQ, walker economy).
- **Harassment**: worker-hunting squads, 60s exemption from rally pulls.
- **Lab report** (AI_LAB_REPORT.md, PROVISIONAL): Tribal 6-0-4 cross-faction;
  Military mirrors stalemate; corner asymmetry measured (3/5 MM mirrors the
  player-corner AI was never attacked). **Caveat**: tuned while zombies are
  still weather — A6b re-tune is budgeted after the Phase 3 threat pass.
  **Update 2026-06-10**: a projectile friendly-fire bug (faction-equality, so
  mirror bullets passed through enemies of the same faction) was found and
  fixed post-report — MM stalemate data is suspect until re-run.

### Track B — The Field (Phase 2)
- **SteeringField autoload**: signed-weight emitters, order-free summed
  sampling, the single home for zombie movement influence going forward.
  ⚠️ **Gameplay-only so far** — it feeds a *bias* into zombie wander direction
  (which is what gives the Caller something to herd with), but zombie
  *locomotion* still runs through `move_and_slide`. The
  physics→deterministic-integration migration — the determinism payoff — is
  **NOT done yet**; NETCODE irreducible #1 remains OPEN (see determinism bullet).
- **Caller** (Tribal, RitualSite, 90 salvage): channels a permanent whistle
  anchor — aims the dead without owning them.
- **Harvest**: Brute/Shambler remains (45s TTL), Walker harvest channel +
  auto-harvest fallback. Flavored salvage income for Tribal.
- The control ladder reads: Hunter *wears* the dead (≤4 defensive thralls),
  Caller *aims* the dead, Beastmaster (future) *keeps* the dead.

### Determinism / netcode substrate
- Record-vs-record CI with **per-component checksums** (units/buildings/
  zombies/salvage/RNG-count) — divergence localizes to a subsystem.
- Known irreducible (**STILL OPEN**): intermittent zombie `move_and_slide`
  physics divergence (~tick 600-720, same build, asset-load sensitive).
  Documented in NETCODE.md. The SteeringField autoload now exists but zombie
  locomotion has NOT migrated onto it yet (the field only biases wander) —
  until that swap, this divergence stays. Phase 2 shipped the field's
  *gameplay* half, not its *determinism* half.
- Float-with-discipline ruling (NOT fixed-point) locked 2026-06-08.
- **WorldConstants autoload** (2026-06-10): map geometry defined once.

### Maps & construction
- **Three authored maps** (MapRecipes.gd, deterministic seed 777): Downtown
  (street-grid city, plazas), Terrace (row-home suburb, arterials), Orchard
  (loose suburb, driveways, vegetation). Regular (scenery) / Lootable /
  Infested building mix per MAP_DESIGN.md. Procedural town remains default.
- **SC-style construction**: BuildCatalog, ghost placement with footprint
  validation, ConstructionSite with channel-to-build (Looter/Walker),
  CommandBus "construct" kind. Ridley test map deleted.

### HUD (2026-06-10)
- SC console study: bottom console (minimap | portrait selection panel |
  3×3 command card with QWE/ASD/ZCV), top-right salvage, control groups
  (Ctrl+1-9 / 1-9), minimap with terrain underlay + live blips + camera
  diamond + click-pan. All code-themed, no scene fragility.

### Art
- Gold sprite family: pro-mode 48px (Brute 64px), idle/walk/attack/death ×
  8 directions, consistent scale and styling anchored on Engineer v1.
  Covered: Rifleman, Heavy Gunner, Looter, Medic, Engineer (Military);
  Walker, Hunter, Shaman (Tribal); Shambler, Runner, Brute (zombies).
- Building map-objects partially generated (see ART_RUN_LOG.md for budget
  and the one CUDA-OOM retry).

## Corrections to the earlier state summary (the ones Matt missed)

1. **Tracks A and B shipped, but with load-bearing caveats** (not "complete").
   Track A's *architecture* is done (defends, harasses, both factions,
   data-driven) but is **not yet validated**: the lab shows Tribal 6-0
   dominance and the Military mirror data was invalidated by a projectile
   friendly-fire bug (faction- vs team-hostility), so the "worthy opponent?"
   exit bar is unproven pending a re-run + Matt's feel-test. Track B's
   *gameplay* (Caller herding, harvest) is done but its *determinism migration*
   (zombies off `move_and_slide`) is **not** — see the Track B / determinism
   notes above. Treat both as "code-complete, feel- and balance-unverified."
2. **Survivors have NO gold-family sprites** — **CLOSED 2026-06-10 (same
   day)**: full §7.3 roster built (Runner/Bolter/Brawler/Saboteur/Chemist/
   Builder + Farm/Radio Station) with gold pro-48 sprites for all six units,
   and CONNECTED on Matt's go — the SettlementHub recruits the new roster,
   the Builder places Farms/Radio Stations, the Saboteur's sound grenade
   routes from ground right-clicks. The Caller also got gold sprites.
   **AI gap CLOSED 2026-06-11**: AIProfiles SURVIVOR shipped (runner
   economy, farm->radio income arm, bolt-line sustain); the title screen
   gained an Opponent picker (Military/Tribal/Survivors) and the lab
   speaks --matchup=S. SvM + MvS validated (economy loops, build order
   completes, army grows). Balance numbers are placeholders pending a
   full A6-style lab pass.
3. **Workshop is a Military building** (not Survivor) — the summary
   misattributed it.
4. **Contamination nuance**: the zombie checksum (zh) is noisy on identical
   builds; "AI regression" claims must use the noise-floor methodology in
   AI_OVERHAUL_PLAN.md, not raw hash equality.

## Blind spots / open items (things Matt didn't know to look for)

- **Fog of war**: none exists. Both the player and the AI have perfect map
  knowledge. This silently inflates the AI (it never scouts) and deflates
  the Tribal ambush identity. Needs a ruling: prototype with a toggle, or
  defer to vertical slice. Related open question: does noise leak through
  fog (hearing a fight you can't see is very on-theme)?
- **Audio**: literally zero sound. The game is ABOUT noise — the first audio
  pass (gunshots at faction-correct loudness, horde moans scaling with
  density) is a thesis feature, not polish.
- **Performance budget**: no formal perf criterion. PerfProbe exists and logs
  rich per-frame data; what's missing is a pass/fail bar (e.g. "≥30 fps with
  300 zombies + 80 units on min spec"). Late-match saturation (~470 units)
  already drags time_scale in lab runs.
- **Tribal elimination condition**: §12#6 placeholder ruling = lose when
  TribalCamp falls, same as other HQs. Design may want "lose when last
  shaman dies" or similar — needs Matt's call.
- **A6b**: AI re-tune after the threat pass, now ALSO motivated by the
  friendly-fire fix invalidating MM mirror data.
- **Corner asymmetry**: measured but uncorrected — map pass should add a
  fairness check (mirrored rush distances, lootable parity per corner).
- **Save/load**: deferred 6+ months (locked). New systems may use IDs but
  don't refactor existing ref-based fields for it.
- **Netcode**: LAST. Hold this line hardest (advisor ruling). The substrate
  work (checksums, determinism rules, SteeringField) is the cheap insurance;
  actual rollback/lockstep waits until the game is worth networking.

## The immediate next things (in order)

1. **Matt's feel-tests** (checklist at top of ART_RUN_LOG.md): vs Military
   AI, vs Tribal AI (exit bar: lose and want a rematch), Caller herding,
   Walker harvest, sprite scale, the three maps, construction flow, new HUD.
2. **Phase 3 — threat pass** (make the horde dangerous): per ROADMAP.md.
3. **A6b re-tune** after Phase 3 (and re-run MM mirrors post-FF-fix).
4. Rulings needed from Matt: fog toggle now vs later, Tribal elimination,
   noise-through-fog.
