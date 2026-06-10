# FINAL OVERNIGHT REPORT — 2026-06-09/10 (read this first, Matt)

## Awaiting YOUR approval (the two plan-first gates — nothing built on these)
1. **docs/AI_OVERHAUL_PLAN.md** (Track A, commit 31527c2) — decisions: (a) difficulty bar
   + setting scope, (b) harass aggression ceiling, (c) AI force-spawn target policy.
   Defaults listed in the doc; "Approved" starts Phase A1.
2. **docs/CALLER_PLAN.md** (Track B, commit 31527c2) — decisions: (1) control model
   (HERD recommended), (2) SteeringField v0 vs quick path, (3) whistle audibility,
   (4) ritual mats stay flavored salvage.

## Shipped tonight (all committed + pushed to origin/main)
**Gameplay (each CI-verified, record-vs-record):**
- a6fe778 Hunter thrall escort (clicking removed — no more horde-triggering; ≤4 defensive thralls)
- 2b8441f Runner + Brute zombie variants on the Shambler chassis (Track C1)
- fae7f18 Military Medic: heal + morale-recovery aura (Track C2) + Barracks row 3
- 4f984dd D8 COMPLETE: all bare gameplay RNG -> SimRng. **CI frontier tick 420 -> 2760**
  (45 sim-seconds bit-identical; remainder is move_and_slide physics = steering-field era)
- 29a2deb D6 hex formations (no transcendentals) + decay demoted to visual-only per
  DESIGN_MASTER §2 — **FEEL FLAG: infested spawn rates no longer accelerate on decayed
  ground; verify Military squatting pressure still feels right**
- 7c1e8af/f93e772 AUDIT/NETCODE doc updates; 316693f parse-hook autoload fix
**Sprites (every unit in the game now has full animated art):**
- d73a39f Rifleman v6 (patrol cap + tac scarf) · 73633c5 HG v3 (torn sleeves + bandana) — closes task #99
- 13a23ce Medic v1 (kneel-bandage anim plays while healing)
- f8007d8 variant-aware zombie sprite roots (Brute art now renders in-game)
- af25148 Runner v1 zombie (sprint cycle) · f461e97 Walker v1 (gather stoop)
- 3390b84 Hunter v1 (bow draw) · 9ab32c3 Shaman v1 (ritual channel loops during force-spawn)
- a05c3f2 Engineer v1 (blowtorch = attack + repair + construct)
**Buildings + props (first-pass library, NOT wired into Building._draw — your curation pass first):**
- assets/buildings/: residential, commercial, industrial, medical, police, civic,
  infested_residential, command_post, barracks, tribal_camp, hunting_lodge, ritual_site, wall
- assets/props/: corpse_fresh, corpse_rising, blood_decal

## Budget
- Start of art phase: 1368 generations. After Phase 2: 985. **Final: 969 remaining**
  (399 used tonight; 16 buildings/props at ~1 gen each). Floor (100) never approached.
- ritual_site landed on retry (first attempt hit a server-side CUDA OOM) — full
  13-building set complete; zero misses.

## Morning play-check list
1. **Hunter**: walks near wild zombies -> collects up to 4 thralls that body-block; NO hordes
   ever fire from a standing Hunter; killing him frees the escort.
2. **Horde texture**: trigger a horde -> ~1 in 7 zombies visibly different (fast sinewy Runner /
   huge slow Brute). A wandering Brute drags a follower cluster; gunfire doesn't bait it.
3. **Medic**: build from Barracks (3rd button, 100 salvage) -> heals nearby wounded (watch
   the kneel-bandage anim), shaken squads recover visibly faster near him.
4. **New sprites**: Rifleman v6 / HG v3 swapped in; Walker/Hunter/Shaman now real art —
   Shaman's staff-raise loops through the whole 7s ritual; Engineer torches things.
5. **Feel checks from the determinism batch**: horde cadence + corpse rates should feel
   IDENTICAL (distribution-equal swaps); infested-house spawn rate near decayed ground is
   the one real change (flat 90s now) — canon per §2 but verify.
6. Buildings/props are loose PNGs in assets/buildings + assets/props for your review —
   say the word and I wire them into the iso renderer next session.

---

# ART RUN LOG — overnight Pixellab pass (2026-06-09)

*Written by the overnight loop. Budget: subscription generations (1368 remaining at
start, no USD credits). Pixellab slot pool = 8 concurrent direction-jobs, so one
animate call (8 dirs) runs at a time — the pipeline below is serialized; each loop
iteration fires the next item when slots free.*

## Found already DONE at start (stale tasks closed)
- #84 HG v2 sprites: 152 PNGs integrated + committed; #86 Shambler v3: 208 PNGs
  integrated + committed; #88 ground tiles: 16 tiles on disk, TILE_FILES mapped.
- Existing fully-animated characters: Shambler v3 (32), Rifleman v5 (32), Looter v3
  (26), HG v2 (24), Brute v1 (32).

## PIPELINE QUEUE (work top-down; mark DONE/RUNNING as you go)

### Phase 1 — finish #99 (Rifleman v6 + HG v3 animations)
- [DONE] Rifleman v6 (f56f4f6f) walk — template walking-8-frames (8 gens)
- [DONE] Rifleman v6 attack — v3, 6f, all 8 dirs (16 gens)
- [DONE] Rifleman v6 death — template falling-back-death (8 gens)
- [DONE] Rifleman v6 downloaded + swapped into assets tree + committed (d73a39f)
- [DONE] HG v3 (1dc69580) idle — template breathing-idle (8 gens)
- [DONE] HG v3 walk — template walking-8-frames (8 gens)
- [DONE] HG v3 attack — v3, 6f, all 8 dirs (16 gens)
- [DONE] HG v3 death (8 gens); downloaded + swapped + committed (73633c5). PHASE 1 COMPLETE, task #99 closed.
- [ ] Download both zips, unpack to assets/sprites/units/military/{rifleman,heavy_gunner}/ (REPLACE v5/v2 trees — keep dir layout action/dir/N.png), parse-check, commit.

### Phase 2 — new characters (create_character PRO mode, 48-64px, low top-down; prompts from ART_ASSET_LIST + style spec; Pixellab can't take image refs — describe the anchors in text per memory note)
- Medic v1 (336acf71-e073-42d0-9b41-2bec09ca01ab) — pro create DONE (20 gens, 80x80). ALL DONE (create 20 + anims 32 gens) — downloaded, wired (_get_sprite_root + _init_sprite + heal-pose hold), committed 13a23ce, parse-clean. Old spec line: attack v3 "kneeling, pressing bandage wrap onto a wound with both hands" 6f all 8 dirs / death falling-back-death. Then download → assets/sprites/units/military/medic/ + wire Medic._get_sprite_root + commit.
- NOTE: slot pool is one-batch-at-a-time (creates + anims share the 8 slots). Serial cadence ~3 min/batch. Character order after Medic: Runner v1 (prompt below) → Walker → Hunter → Shaman → Engineer.
- [DONE] Runner v1 (a30d9973) — create 20 + anims 32 gens; downloaded + committed af25148. Original prompt spec: "fast sprinting fresh zombie, recently turned, less decayed than a shambler, pale grey-pink raw sinew flesh, torn civilian clothes still recognizable, lean wiry frenzied build, wide-open jaw, aggressive forward-lunging predatory posture, blood-streaked, desaturated ashen palette with dried-blood red accents, bleak horror pixel art, 28 Days Later infected register, grimy post-apocalyptic". Anims: idle breathing-idle / walk = running-8-frames (it RUNS) / attack v3 "frenzied sprinting lunge, clawing and biting" 6f / death falling-back-death.
- [ ] Runner zombie (#13) — variant JUST built in code (fast fresh frenzied).
- [DONE] Walker v1 (121d5c4b) — f461e97. Gather anim plays during channel.
- [DONE] Hunter v1 (64245e95) — 3390b84. Bow-draw attack, CombatUnit wiring.
- [DONE] Shaman v1 (d9df06c8) — 9ab32c3. Ritual channel loops during force-spawn.
- [DONE] Engineer v1 (91e256ea) — a05c3f2. Blowtorch = attack + repair + construct anim.

## PHASE 2 COMPLETE (00:20). Balance: 985 generations remaining (1015 used total; ~383 tonight).
Every unit in the game now has full animated sprites: Looter, Rifleman v6, HG v3,
Medic, Engineer (Military); Walker, Hunter, Shaman (Tribal); Brawler (Survivor);
Shambler, Runner, Brute (zombies). Brawler uses the brute tree note — see memory.
- [ ] Engineer (Military #16).
- [ ] (skip Demolitionist #18 — no unit in code; skip Crawler #12 — Tribal-created units not built)
- Each then needs 4 animate calls (idle/walk/attack/death). Attack actions: Medic "kneeling bandaging motion"; Runner "frenzied sprinting lunge bite" (+ walk = running-8-frames!); Walker attack = none in code (gatherer — generate anyway for library? SKIP attack, gen idle/walk/death + "picking-up" as gather); Hunter "drawing and loosing a recurve bow"; Shaman "raising bone staff, ritual channeling"; Engineer "swinging blowtorch".

### Phase 3 — buildings (create_map_object — auto-delete in 8h, download SAME iteration)
- [RUNNING 00:21] residential=0ed02b62, commercial=038d7f9c, industrial=28e82fa9, medical=31437e36 (4 jobs, ~30-90s each)
- [ ] QUEUE NEXT: police (160x144 "abandoned police station, barred windows, faded insignia, reinforced doors, institutional, dark blue-gray"), civic (176x144 "abandoned civic building school columns broken windows weathered khaki-stone"), infested-residential variant (128x128 "...overrun and infested, dark stains, clawed walls, black ichor, ominous"), CommandPost (160x144 sandbagged military outpost olive netting antennas), Barracks (144x128 reinforced tent-and-container olive), TribalCamp (160x144 bone totems skull poles hide tents central pyre), HuntingLodge (144x128 hide-and-bone antlers drying racks), RitualSite (144x112 circle of bone totems skulls stone altar), Wall segment (64x64 scrap metal sandbags razor wire).
- Save to assets/buildings/<name>.png, commit batches. Wiring into Building._draw DEFERRED (notes only).

### Phase 4 — props (#36-#37 corpses + blood decal #43; rest exist from #97)

### Credits log
- Start: 1368 generations.
- Rifleman v6 walk (8 template jobs) — queued.

## Iteration notes
- 21:2x — queue full at 7/8 after walk batch; wrote this log; local stale-task audit done.
