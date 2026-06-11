# Image-to-Playable-Map Pipeline — Multi-Phase Plan

*Matt's plan, 2026-06-11 (canonical for this pipeline). Builder status
appendix at the bottom. Supersedes the builder draft of the same date.*

## Context

Carrion / THE LONG WAKE needs maps at StarCraft scale that look like the
reference image (Gemini, "StarCraft 1 style zombie-themed map": Military
fortified compound, Survivor refuge with greenhouses, Tribal palisade camp,
contested neutral ground — infested grocery, abandoned suburbs, river
crossing). TownPlanner's tile-grid output doesn't approach this quality and
never will; hand-authoring this density per map is too expensive. The
solution: AI-generated map illustrations in, playable Godot maps out, with
game objects (buildings, terrain, navigation, lootables, faction territory)
extracted from the illustration.

## Architectural Decisions

1. **The illustration is the source of truth for visuals.** The game does
   not re-render the map from tiles; the illustration IS the rendered map,
   a background image at appropriate zoom. Game objects draw on top. This
   eliminates the tile-checkerboard problem entirely.
2. **Structure is extracted semi-automatically.** Claude's image analysis
   produces structured JSON (building footprints, terrain regions, nav
   polygons, faction territory hints, lootables, special features). Human
   verification refines it.
3. **Game objects anchor to illustration coordinates.** Buildings become
   clickable objects with HP/ownership at their pixel positions; roads
   become nav surfaces with traversal cost modifiers; rivers are impassable
   except at bridges.
4. **Resolution strategy.** Generate at 4096x4096+ where the generator
   allows; strategic zoom = downscaled, tactical zoom = native; low-end
   machines take half-res textures.
5. **Scope boundary.** This serves the 9 campaign maps + 6-10 curated
   multiplayer maps. TownPlanner remains for unlimited procedural skirmish.

## Phase 1: Proof of Concept (one map, end-to-end)

- **1.1 Image preparation** — verify dims/quality/playable bounds; save to
  `assets/maps/proof_of_concept/source.png`.
- **1.2 AI vision extraction** — Claude image analysis → structured JSON:
  `map_size`, `playable_bounds`, `terrain_regions` (water / vegetation_dense
  / open_ground / road_network polygons), `buildings` (id, type, footprint,
  hp, intact, lootable, infested, faction_hint), `structures` (bridge /
  wall_section / totem), `faction_territories` (polygon + spawn_position
  per faction), `ambient_objects` (cars, debris; blocks_movement/los).
- **1.3 Verification** — render the JSON as a colored overlay on the source
  image; visually verify; fix misses by hand; save `structure.json`.
- **1.4 Godot scene generation** — source image as background; MapBuilding
  nodes per building; NavigationRegion2D per terrain region with costs;
  bridges/walls/totems; spawn markers + territory boundaries; ambient
  colliders. Output loads as a playable map.
- **1.5 Integration test** — camera, selection/movement, pathfinding around
  buildings and through roads, buildings targetable/destructible, river
  impassable except bridges, territories feed AI, infested buildings spawn
  shamblers, lootables loot. Failures triaged to extraction vs generation
  vs game systems.

## Phase 2: Pipeline Generalization

- **2.1** Prompt template for consistent map illustrations (faction
  territories, contested ground, natural barriers, strategic resources;
  muted palette; 4096x4096; per-map details slot).
- **2.2** Generate three more maps (Pripyat hospital district, Detroit
  residential, Centralia downtown, etc.) — variation from per-map details,
  not style drift.
- **2.3** Run each through 1.2–1.5; document and handle new edge cases.
- **2.4** Refactor into `python tools/image_to_map.py <illustration.png>`.

## Phase 3: Game System Integration

- **3.1** Image-map code path in Main beside TownPlanner (both coexist).
- **3.2** Camera/rendering at StarCraft scale (zoom range, edges, perf).
- **3.3** Minimap = downsampled illustration + live overlay markers.
- **3.4** AI compatibility: territories feed AIController/AIStrategist.
- **3.5** Save/load flagged (deferred per design doc).

## Phase 4: Authoring Tool (Matt-paints-areas)

- **4.1** Region-painting UI (semantic colors, building markers, territory
  hints, ambient objects).
- **4.2** Painted regions → image generator → final illustration matching
  Matt's composition.
- **4.3** Output runs through the Phase 2 pipeline. Optional; after the
  campaign maps.

## What to do first

Phase 1 is the unblocker; everything else is speculation until one
image-based map plays end-to-end. Don't parallelize phases.

## Risk assessment

1. **AI vision extraction quality** (highest): pixel-coordinate precision
   is the make-or-break. Test extraction accuracy FIRST; poor accuracy
   means more manual verification per map (fine, but changes time cost).
2. **Scale mismatch**: SC-scale maps may expose perf/AI/balance issues
   (Phase 3).
3. **Visual register drift across maps**: mitigate with Map 1 as the style
   reference for subsequent generations.
4. **Integration** (lowest): the deterministic substrate, units, and AI
   should work on any map.

---

## Builder status appendix (2026-06-11)

- Much of 1.4/3.1 already exists from the Willow Creek prototype
  (`9fe2ccd`): backdrop loader, phantom lootable/blocker nodes with exact
  inverse-projected nav polygons, spawn overrides, boundary fencing,
  title-screen + `--image-map=` entry points. This plan's scene-generation
  step extends that loader rather than starting fresh.
- Known Willow Creek defects roll into 1.4/1.5: build-placement validity
  on image maps, rooftop occlusion (cookie-cut buildings from the
  backdrop), minimap underlay, camera bounds.
- PoC source saved: 1408x768 (generator cap; below the 4096 target —
  regen at higher res later; pipeline is resolution-agnostic). Baked-in UI
  (bottom-left resource bar/minimap, top-left logo) excluded via
  playable_bounds + blocked regions. Baked zombies in the infested center
  are decorative; future prompts should exclude creatures.
