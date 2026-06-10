# WORKDAY SUMMARY 2026-06-10 (Matt at work — read this + ROADMAP.md + AI_LAB_REPORT.md)

## Track A — COMPLETE (code; your feel-test is the exit bar)
A4 Tribal AI a1ec528 · A5 harassment 2d5bc8f · A6 lab report e3d8fd0
(A1-A3 were morning: da3aeeb / 7e0966f / 2f95598)
Lab headline: Tribal 6-0-4 cross-faction (hunter rush decides), Military
mirrors stalemate (attrition equilibrium), CORNER ASYMMETRY measured (map-pass
input). All balance numbers provisional until the threat pass (A6b budgeted).

## Track B — COMPLETE through B4 (code)
B1 SteeringField v0 bcef9e9 · B2 Caller aed2ada · B3 harvest 7bbe0e2 ·
B4 sanity: TT match = 19 harvests, rituals firing, both Tribal AIs healthy.

## Sprite redo queue (gold pro-48 family) — 5 of 6 shipped
HG v4 7012d8d · Rifleman v7 d8b2766 · Looter v4 80edc07 · Medic v2 a99f556 ·
Shambler v4 bd67c1e · Brute v2 (64px) IN FLIGHT (a0e177f9, anims finishing on
the loop — final commit lands before you're home).

## Budget: 713 generations remaining (Brute v2 needs ~40 more; floor 100 safe).

## Evening feel-test checklist (the real exit bars)
1. Play vs the Military AI, then vs the Tribal AI (title screen as usual; AI
   faction now matches the matchup) — bar: lose a game you tried to win and
   want a rematch. Expect Tribal to feel TOO strong (lab says so) — that's
   A6b's job, tell me where it crossed from pressure into unfair.
2. Build a Caller (Ritual Site, 90): close right-click = whistle (line+ring
   telegraph), far right-click = walk. Herd a cluster at the enemy. Kill him
   mid-whistle: drift stops instantly.
3. Watch Walkers: when local lootables run dry they harvest remains piles
   (dark mounds, bone fleck) automatically. Right-click a Brute pile = 40.
4. Sprite scale: whole roster should now read as ONE family. Flag any unit
   that still feels off-scale or off-style.
5. Walker roaming feel-flag: they range ~2x farther before idling (A4 fix).

---

# SPRITE REDO QUEUE (Matt directive 2026-06-10): match the gold pro-48px family
# (Engineer/Shaman/Hunter/Walker/Runner v1). Per character: pro create -> 4 anim
# batches (idle breathing-idle / walk walking-8-frames / attack v3 custom 6f all
# 8 dirs / death falling-back-death) -> download -> swap tree -> commit.
- [RUNNING] HeavyGunner v4 (437297e8-db17-436a-81ff-867ad7c52f94) create. Attack v3: "leaning back braced, firing heavy belt-fed machine gun from the hip, muzzle climb". Tree: military/heavy_gunner.
- [ ] Rifleman v7: "post-apocalyptic military rifleman, grizzled bearded soldier in worn olive fatigues and patrol cap, tactical scarf around neck, plate carrier with pouches, maintained carbine rifle, visible weathered face, desaturated olive coyote gunmetal palette, bleak realistic pixel art, The Road register". Attack v3: "standing braced, aiming rifle and firing with sharp recoil kick". Tree: military/rifleman.
- [ ] Looter v4: "post-apocalyptic military looter-scavenger, lean wiry soldier in worn olive fatigues, heavy scavenging pack with slung sacks and scrap, large revolver magnum sidearm drawn, weathered confident face, desaturated olive coyote palette, bleak realistic pixel art". Attack v3: "aiming a heavy revolver two-handed and firing a single deliberate shot". Tree: military/looter.
- [ ] Medic v2: same prompt as Medic v1 (red-cross satchel, no rifle) but pro 48px family scale. Attack v3: "kneeling down, pressing a bandage wrap onto a wound with both hands". Tree: military/medic.
- [ ] Shambler v4: "slow shambling zombie, desiccated gaunt civilian in tattered ragged clothing, grey-green rotted flesh, hunched lurching posture, vacant dead eyes, bleak horror pixel art, grimy". Walk = scary-walk template. Attack v3: "lurching grab and bite". Tree: zombies/shambler.
- [ ] Brute v2 AT 64PX: "huge hulking zombie, massively muscled and swollen, towering bulk, thick rotted hide, slow devastating presence, bleak horror pixel art". Walk = scary-walk. Attack v3: "massive overhead two-armed smash". Tree: zombies/brute.
# Budget at queue start: ~949 gens (after HG create). ~330 needed total. Floor 100.

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
