# THE LONG WAKE — Art Asset Generation List (PixelLab unattended pass)

*A prioritized, prompt-per-asset list for a full-day PixelLab generation run via Claude Code. Read WORKFLOW_PLAYBOOK.md §4 (PixelLab techniques) and ART_PIPELINE_RESEARCH.md first. This run produces a **first-pass library to replace placeholders** — raw material Matt curates later, NOT finished hero art. Consistency is PixelLab's weak axis; the mitigations below fight it but won't make it perfect.*

---

## META-INSTRUCTIONS (read before generating anything)

**Prerequisites (Matt does these before the run):**
- The three faction style anchors are saved at `assets/concept/{military,survivor,tribal}_anchor.png`. Use the matching one as the **style reference / consistent-style input** for every asset of that faction. This is the #1 consistency lever.
- A credit budget is set. **Call `get_balance` first.** Work the priority tiers in order; **stop when the budget cap is reached** and report where you stopped. Prefer basic models (1 credit) where quality allows; use Pro/style-reference (40 credits) only where consistency demands it.

**Hard rules:**
- **Style/palette consistency:** for each faction, generate with that faction's anchor as the style reference, **reuse the same `seed` across a batch**, and after generation **run the Reduce-Colors / quantization pass against one canonical palette per faction** (define a bleak world palette + per-faction accent — see Palettes below). This is the single biggest fix for roster drift.
- **Projection:** the game is **2:1 dimetric isometric** (tile = 2× wide as tall). Ground tiles render on a 64×32 diamond. Units/buildings are iso-facing sprites that sit on that grid.
- **Register (every prompt inherits this):** bleak, grimy, desaturated, long-collapse post-apocalypse — *The Road / Project Zomboid / 28 Days Later*. Muted browns, grays, olive, rust. Worn, weathered, lived-in. NOT bright, NOT cartoony, NOT clean.
- **The generative rule (keep factions coherent):** **face = identity** (Military faces visible/grizzled; Survivor faces hidden behind gas masks; Tribal faces bare but scarred/marked). **material = relationship to the old world** (Military: manufactured mil-gear; Survivor: scavenged civilian scraps; Tribal: bone, hide, sinew).
- **Sizes:** units ≥48px canvas then downscale (PixelLab is weak ≤16px — never generate units small). Generate larger and let the game downscale.
- **Build the roster as `create_character` (persists), NOT map-objects** (those auto-delete in 8h). Buildings/props can be map-objects but download them promptly.
- **Non-blocking fan-out:** every create-tool returns a job ID immediately. **Queue ALL jobs in a tier first, then batch the `get_*` / download calls.** Don't wait on each one. This is the biggest throughput win.
- **Read the Godot MCP resources** (`pixellab://docs/godot/wang-tilesets`, `.../isometric-tiles`) before wiring tiles — they include a headless GDScript converter so you don't hand-roll the TileSet.
- **Save outputs organized:** `assets/sprites/units/<faction>/<unit>/`, `assets/tiles/`, `assets/buildings/`, `assets/props/`. For ground tiles and where straightforward, wire them into the iso `GroundTiles` TileMapLayer; for units/buildings, save the sprite sheets ready for `AnimatedSprite2D` and leave wiring notes — don't break gameplay.
- **Log everything:** write `docs/ART_RUN_LOG.md` — every asset generated, its job ID/path, credits spent, running total, and which tier you reached. So Matt can review and resume.
- **Note on iso tiles:** PixelLab has NO isometric Wang/autotiling — iso ground is per-tile (`create_isometric_tile`). Seamless terrain *transitions* are deferred (manual or the render-to-iso pipeline later). First pass = clean single tiles per terrain.

**Palettes (Matt: confirm or adjust before the run):**
- **World base:** desaturated — asphalt gray, dead-grass khaki, dirt brown, concrete, rust, ash. (Find/build a Lospec palette ~16–24 colors.)
- **Military accent:** olive drab, coyote tan, gunmetal black.
- **Survivor accent:** muddy earth tones, faded canvas, dull green, improvised-gear browns.
- **Tribal accent:** bone white, leather brown, skin, charcoal, dried-blood red.

---

## PRIORITY TIER 1 — Ground tiles (foundation; the 2:1 migration just unblocked this)

`create_isometric_tile`, 64×32-target, world base palette, **same seed across all of these for cohesion**, "block"/"thin" shape as appropriate. Prompt the CENTER of the tile, not a scene.

1. **Asphalt road** — "cracked weathered asphalt road surface, faded lane markings, potholes, oil stains, post-apocalyptic decay, top-down isometric ground tile."
2. **Sidewalk / concrete** — "cracked grey concrete sidewalk slab, weeds in the cracks, stained, worn isometric ground tile."
3. **Dead grass / yard** — "patchy dead yellow-brown grass, overgrown weeds, dry dirt patches, neglected suburban lawn, isometric ground tile."
4. **Dirt / bare ground** — "packed brown dirt ground, dry cracked earth, sparse pebbles, isometric ground tile."
5. **Dirt road / path** — "worn dirt path, tire ruts, scattered gravel, isometric ground tile."
6. **Parking lot** — "faded asphalt parking lot, worn painted parking lines, cracks and weeds, isometric ground tile."
7. **Rubble / debris** — "pile of broken concrete rubble, shattered brick, twisted rebar, post-collapse destruction, isometric ground tile."
8. **Overgrowth / vegetation** — "wild overgrown vegetation reclaiming the ground, tangled weeds and grass, creeping vines, isometric ground tile."
9. **Cracked earth / wasteland** — "barren cracked dry earth, dead and grey, ashen, isometric ground tile."
10. *(optional)* **Stagnant water** — "murky stagnant dark water puddle, scummy surface, isometric ground tile." (only if the map uses water)

## PRIORITY TIER 2 — Zombies (most numerous entity on screen; defines the threat)

`create_character`, ≥48px, world/ashen palette, animations: **idle, walk (shamble), attack, death**, 8 directions. Style: rotted, grey-green flesh, tattered clothing.

11. **Shambler** (baseline) — "slow shambling zombie, rotting grey-green decayed flesh, tattered ragged clothing, hunched lurching posture, vacant, gore, bleak horror pixel art." (the workhorse — make this one count)
12. **Crawler** (Tribal-made, zergling-like) — "fast feral zombie moving on all fours, lean and sinewy, hunched predatory crawl, twisted limbs, rotted flesh, ritual bone markings, quick and dangerous." (animate the crawl + a fast lunge attack)
13. *(if budget)* **Runner** — "fast sprinting fresh zombie, less decayed, frenzied aggressive run, deadly individual." (future variant)
14. *(if budget)* **Brute** — "huge hulking zombie, massively muscled and swollen, slow but devastating, thick rotted hide, towering bulk." (future variant — large canvas)

## PRIORITY TIER 3 — Units you control most (Military roster gaps + Tribal slice)

`create_character`, ≥48px, faction anchor as style reference + faction accent palette, **8 directions**, animations: **idle, walk, attack, death**. Use `create_character_state` later for team-color/doctrine variants.

*Note: Looter and Rifleman already have sprites — verify they match the anchor register; only regenerate if off-style.*

**Military** (military anchor; olive/tan/gunmetal; faces visible, grizzled; manufactured gear):
15. **Heavy Gunner** — "post-apocalyptic military heavy gunner, bulky bearded soldier in worn olive plate carrier and helmet, hauling a large belt-fed machine gun, draped with ammo belts, heavier broader silhouette than a rifleman, grizzled, bleak realistic pixel art."
16. **Engineer** — "post-apocalyptic military combat engineer, soldier in worn fatigues and tool harness, carrying a blowtorch and satchel of tools and grenades, utility webbing, practical, grimy, bleak realistic pixel art."
17. **Medic** — "post-apocalyptic military field medic, soldier in worn fatigues with a red-cross-marked medical bag and supply pouches, weathered, grim, bleak realistic pixel art." (distinct readable medic silhouette — important for the focus-fire game)
18. **Demolitionist** — "post-apocalyptic military demolitions specialist, soldier in heavy reinforced gear, carrying breach charges and explosives bandolier, blast goggles, scarred, bleak realistic pixel art."

**Tribal** (tribal anchor; bone/leather/skin; bare scarred faces; bone-and-hide gear):
19. **Walker** (economy, immune) — "feral tribal scavenger, lean figure in bone ornaments and hide wraps, dreadlocks, painted with ash and dried blood, carrying scavenged scrap in a hide satchel, walks calmly and unafraid among the dead, barefoot, bleak ritual pixel art." (the iconic 'strolls through the horde' unit)
20. **Hunter** (silent ranged) — "feral tribal hunter, sinewy scarified warrior with dreadlocks and bone ornaments, drawing a crude recurve bow, quiver of arrows, antler and skull adornments, hide loincloth, barefoot, predatory, bleak ritual pixel art."
21. **Shaman** (force-spawn signature) — "feral tribal shaman, gaunt ritual figure draped in bones, skulls, and animal hides, antlered headdress, holding a bone ritual staff, painted in blood and ash, ominous and otherworldly, bleak ritual pixel art."

## PRIORITY TIER 4 — Buildings (map structures + faction bases)

`create_map_object` (tall iso, sits on the diamond grid), faction/world palette. Bleak boarded-up post-collapse versions. Generate at the building's footprint scale (residential ~2×2 tiles, larger for institutional/HQ).

**Map / lootable buildings** (world palette, abandoned):
22. **Residential house** — "abandoned suburban house, boarded windows, peeling paint, sagging roof, overgrown yard, post-apocalyptic decay, isometric building."
23. **Commercial / store** — "abandoned small storefront shop, smashed display windows, faded signage, looted interior, isometric building."
24. **Industrial / warehouse** — "abandoned industrial warehouse, corrugated metal walls, rust, broken loading doors, isometric building."
25. **Medical / hospital** — "abandoned medical clinic building, faded red cross, broken glass doors, institutional concrete, isometric building."
26. **Security / police** — "abandoned police station, barred windows, faded insignia, reinforced doors, institutional, isometric building."
27. **Civic** — "abandoned civic building, school or government hall, columns, broken windows, weathered institutional facade, isometric building."
28. **Infested building variant** — a darker, overgrown, viscera-marked version signaling 'zombies spawn here' (apply to residential/commercial — "...overrun and infested, dark stains, clawed walls, ominous").

**Faction structures** (faction palette + register):
29. **Command Post** (Military HQ) — "fortified military command post, sandbagged outpost built from a repurposed building, olive netting, antennas, barricades, makeshift institutional military, isometric building."
30. **Barracks** (Military) — "military barracks, reinforced tent-and-container structure, fortified, olive drab, isometric building."
31. **Tribal Camp** (Tribal HQ) — "tribal encampment, bone totems and skull poles, hide tents around a central pyre, ritual markings, primitive, isometric structure."
32. **Hunting Lodge** (Tribal) — "tribal hunting lodge, hide-and-bone structure draped with antlers, skulls, and drying racks, isometric structure."
33. **Ritual Site** (Tribal) — "tribal ritual site, circle of bone totems and skulls around a stone altar, dark ominous ceremonial ground, isometric structure."
34. **Wall** (defensive) — "makeshift defensive barricade wall, scrap metal, wood, sandbags, razor wire, post-apocalyptic fortification, isometric tile-segment."
35. ~~*(if budget — Survivor, future)* **Settlement Hub, Farm, Radio Station** — defer; Survivor isn't built.~~ **DONE 2026-06-10** — Survivor faction built + connected; all three buildings generated (`assets/buildings/{farm,radio_station,settlement_hub}.png`), plus the full six-unit Survivor roster at gold pro-48 (`assets/sprites/units/survivor/{runner,bolter,brawler,saboteur,chemist,builder}`) and the Tribal **Caller** (`tribal/caller`).

## PRIORITY TIER 5 — Props & decor (sell the world)

`create_map_object` / small iso sprites, world palette.

36. **Corpse — generic** — "fresh human corpse lying on the ground, sprawled, bloodied, post-apocalyptic, isometric prop." (the corpse economy needs this — generate a base; team-tint via `create_object_state`)
37. **Corpse — risen/stirring** — a variant mid-reanimation (twitching, clawing up) for the rise moment.
38. **Wrecked car** — "rusted abandoned wrecked car, broken windows, flat tires, post-apocalyptic, isometric prop." (×2–3 variants/colors)
39. **Debris pile** — "pile of post-apocalyptic debris, broken furniture, trash, scrap, isometric prop."
40. **Dead tree** — "bare dead leafless tree, gnarled, grey, isometric prop." + **overgrown tree** (wild reclaimed green).
41. **Streetlight / utility pole** — "leaning broken streetlight pole, dead, rusted, isometric prop."
42. **Barrels / crates** — "rusted oil barrels and weathered wooden crates, scattered loot containers, isometric prop."
43. **Blood/scent splatter decal** — ground decal for the blood mechanic (later) — "dark blood splatter stain on the ground, isometric decal."

## PRIORITY TIER 6 — UI / icons (lowest priority; may be better hand-done or deferred)

44. Faction emblems (Military / Tribal / Survivor) — small insignia icons.
45. Unit portraits — you already have 3 faction portraits; per-unit portraits are a stretch goal.
46. Ability/HUD icons — force-spawn, suppression, gather, build — small readable iso/flat icons.

*(Tier 6 is a stretch — only if budget and time remain after 1–5. Icons often read better hand-made; don't burn the budget here.)*

---

## Suggested run order within the budget
Tier 1 (tiles, ~10) → Tier 2 (zombies, 2–4) → Tier 3 (units, ~7) → Tier 4 (buildings, ~13) → Tier 5 (props) → Tier 6 (icons). Fan out each tier's jobs together, download in batch, reduce-colors against the palette, save organized, log credits, then move to the next tier. **Stop at the budget cap and report.**
