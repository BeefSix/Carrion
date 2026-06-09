# THE LONG WAKE — Map & Tile Art Pipeline Research

*Compiled 2026-06 from a 5-thread deep-research pass. Question: how to produce isometric tile maps and tilesets that look cohesive AND are "map-correct" (seamless, grid-aligned, projection-correct) for a competitive Godot 4 RTS, given an existing PixelLab + Gemini + Godot stack and a bleak detailed-pixel-art register.*

---

## TL;DR — the decision

1. **The hardest thing you want does not exist as a tool.** No 2026 tool auto-generates a *seamless, edge-matched, isometric Wang/blob terrain set*. PixelLab does this for *top-down* but iso is one-tile-at-a-time. Every AI-2D path leaves you hand-assembling and edge-fixing iso tiles. Consistency across a large tileset is AI-2D's *weakest* axis — and an iso tileset is exactly the thing that most demands consistency.

2. **The surprising winner is the oldest technique: render-to-iso (3D → 2D).** Model (or AI-generate) in 3D, render through a *fixed orthographic iso camera with fixed lights*, blit the 2D result. This is how Diablo II / StarCraft / Age of Empires II made their "2D" art. It is the **consistency winner by a mile**, it fits your bleak-realistic register better than pixel art or AI-2D, it gives you **free normal maps for dynamic lighting**, and it's **deterministic and re-renderable**. AI-3D tools (Tripo/Meshy/Rodin) crossed the "usable for base meshes/props" line in 2026, which removes the historical reason this pipeline was expensive.

3. **Possible root cause of "doesn't map correct": your projection is non-standard.** Your IsoView uses a ~4:3 oblique (the 0.75 vertical factor). The industry standard — and what every tool, importer, and render rig assumes — is **2:1 dimetric** (tile width = 2× height, e.g. 64×32, a 0.5 factor). A 4:3 oblique projection fights Godot's iso TileMap, Tiled, and the Blender iso rigs. If you're early enough to reconsider, moving to 2:1 dimetric aligns you with the entire ecosystem. **This is the single highest-leverage flag in this report.**

4. **Competitive maps must be hand-authored and symmetric.** The map is the *primary* balance lever (Brood War was balanced via maps, not unit stats). Procedural is viable only with a symmetry/fairness post-pass — and any procedural map gen must run off `SimRng` for lockstep determinism.

---

## 1. The honest gap (AI-2D iso tiles)

- **PixelLab** is the most game-tile-specific tool and the best fit to your stack (Godot guides, MCP-scriptable). It auto-generates true **top-down Wang / dual-grid (15) / 3×3** sets with terrain chaining via MCP (`create_topdown_tileset`). But its **isometric** tool generates **one tile at a time** (16/32px, shape presets Thick/Thin/Block) — *no iso Wang/blob auto-set*. ([pixellab.ai/docs](https://www.pixellab.ai/docs/tools/create-isometric-tile), [pixellab.ai/mcp](https://www.pixellab.ai/mcp))
- **Scenario** wins at *style consistency via custom-trained models* (train a LoRA on 8–20 reference tiles, or a Flux-Kontext "photo→iso-building" action-LoRA). Strong for on-style **buildings/props at scale**, not seamless terrain Wang sets. Edge-matching is achieved by training-on-edges + manual inpainting, *not* an automatic tiling engine — discount the "align, tile, ship" marketing. ([scenario.com/blog iso tiles](https://www.scenario.com/blog/build-isometric-game-tiles-with-ai), [flux-kontext-lora](https://www.scenario.com/blog/flux-kontext-lora-isometric-building-tiles))
- **Retro Diffusion** (Aseprite plugin, one-time ~$65) — best pixel-art palette/seamless control, **top-down tiling only**.
- **Sprite-AI**'s own honest verdict (most credible neutral source): organic textures tile great; directional tiles are mediocre; **Wang/Blob sets are "not suitable (yet) — a generation problem."** ([sprite-ai.art](https://www.sprite-ai.art/blog/seamless-pixel-art-tiles))
- **Research frontier** that may close this gap soon: Boris-the-Brave's **Non-Manifold Diffusion** (co-generates a whole interlocking tile set so edges match by construction, Feb 2025) and **Tiled Diffusion** (CVPR 2025, many-to-many tile connectivity). Not shipping products yet. ([boristhebrave.com](https://www.boristhebrave.com/2025/02/04/generating-tilesets-with-stable-diffusion/), [tiled-diffusion](https://madaror.github.io/tiled-diffusion.github.io/))

**If you stay AI-2D:** generate per-tile iso with a palette/style-locked model, then assemble Wang/blob manually using circular-padding / 50%-offset seam cleanup. It works; it's manual labor; and consistency stays your weak point.

---

## 2. The recommended backbone — render-to-iso (3D → 2D)

**Why it's right for *this* project specifically** (not generic advice — these are the axes where it beats the alternatives, and they're all your axes):

- **Consistency:** a locked orthographic camera + reused lights make *every* asset — tile, prop, building, unit — share identical perspective, scale, and light direction. This is the exact thing you're fighting, and the exact thing AI-2D and hand-pixel are *worst* at.
- **Register:** bleak, realistic, atmospheric (The Road / Project Zomboid) is what 3D rendering does *best*. Your faction concept art is already semi-realistic — 3D renders match that register more naturally than pixel art.
- **Dynamic lighting (the sleeper win):** render a **Normal pass** from the same Blender scene → drop onto Godot `Sprite2D`/`CanvasItem` (natively supported) → your flat sprites react to in-game lights. For a zombie apocalypse this is *enormous*: flashlight cones, muzzle flashes, the Heavy Gunner's tracers, fires, day/night dread. Nearly free here, nearly impossible with hand-pixel. ([Blender normal pass](https://docs.blender.org/manual/en/latest/render/layers/passes.html), [GameMaker normal maps explainer](https://gamemaker.io/en/blog/using-normal-maps-to-light-your-2d-game))
- **Determinism / re-render:** change the iso angle or palette later → re-render the whole set from source. Version-controllable, reproducible. (Pure art pipeline — offline, render-only — so it's orthogonal to your sim-determinism rules.)

**The workflow:**
1. **Get the 3D asset.** AI-generate a base mesh from text or your concept art, or hand-model. 2026 tool guidance from independent testers:
   - **Tripo / Tripo3D** — cleanest *quad topology*, fastest, has a **Godot plugin**. Best base-mesh quality. ([tripo3d.ai](https://www.tripo3d.ai/))
   - **Rodin / Hyper3D** — ultra-photoreal 4K PBR, high-poly-quad option, full commercial rights, Shutterstock-licensed training data (cleaner provenance). Best for realistic hero props/buildings. ([hyper3d.ai/pricing](https://hyper3d.ai/pricing))
   - **Meshy.ai** — closest to a *full pipeline* (texture + auto-rig + 500+ animations + one-click Godot export); free plan is CC-BY (must credit), paid plans you own outputs. ([meshy.ai](https://www.meshy.ai/), [ownership](https://help.meshy.ai/en/articles/10137554-what-is-the-ownership-of-the-generated-models))
   - **TRELLIS** (open-source, self-host) — top visual fidelity, messier topology.
   - Reality check from every independent tester: expect a **~20% manual cleanup pass** (retopo/UV/weights) for anything beyond background props. Raw AI topology is often triangulated. Tripo/Rodin's quad output minimizes this.
2. **Clean up in Blender** (1 unit = 1m so all assets share scale).
3. **Render through a fixed iso-camera scene** — the consistency guarantee. Use **Orthographic** camera, **Sun lamps reused across every asset**, render **RGBA + Straight Alpha** (avoids the classic sky-color seam bug). For 2:1 game-iso the canonical Blender setup (Clint Bellanger / Flare): RotX 60°, RotZ 45°, render a plane to 64×32. Free rigs: **Create IsoCam** addon, **Blender 2D Sprite Studio**. Parent camera+lights to an Empty and rotate in 45° steps for 8 facings (Bellanger publishes the render script). ([clintbellanger.net](https://clintbellanger.net/articles/isometric_tiles/), [create-isocam](https://github.com/jasonicarter/create-isocam))
4. **Render the Normal pass alongside the color pass** for dynamic lighting (strictly better than inferring normals from a 2D image via Laigter/Sprite DLight — you have the geometry, use it).
5. **Optional pixel pass** (render low-res or posterize + hand-touch) if you want crunchier pixel fidelity; otherwise ship the clean renders.

**The cost, honestly:** Blender rig setup + learning, an AI-3D subscription, and this *supersedes* the pure-2D AI path (Gemini/PixelLab become concepting/reference tools, not final-art tools). For a solo dev moving fast that's a real investment — so **de-risk it before committing** (see §6).

**The lower-disruption alternative:** keep Gemini/PixelLab for characters, but use render-to-iso *just for ground tiles and buildings* (the things that most need to tile and stay consistent). Tiles are simple 3D — a textured plane or a low box — so the 3D barrier is tiny there. This is a sane hybrid if the full pivot feels like too much at once.

---

## 3. Map authoring & "map-correct" placement

- **Tooling for iso in Godot 4:** realistically two choices — **Godot's built-in TileMapLayer** (Tile Shape = Isometric; best grid-correctness since gameplay and tiles share one coordinate space) or **Tiled + YATI importer** (best iso authoring + Wang/terrain tooling; costs an import step). **LDtk and Sprite Fusion are square-grid tools** — LDtk has the best autotiling of the four but *no native diamond-iso mode*, so it's a poor fit for a true iso RTS. ([YATI](https://github.com/Kiamo2/YATI), [Godot tilemaps docs](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilemaps.html))
- **Godot's iso autotiling is the documented weak spot** — historically buggy ([issue #58714](https://github.com/godotengine/godot/issues/58714)), still finicky. Plan to **script tile placement** from your logical grid (off `SimRng`) or use **TileMapDual** (dual-grid autotiling that explicitly supports isometric, ~15 tiles). ([TileMapDual](https://github.com/pablogila/TileMapDual))
- **The architecture you already have is correct:** store the map as a plain integer 2D grid; do all gameplay (movement, fields, targeting) in cell coordinates; project to/from screen *only* at the render/input boundary (`map_to_local`/`local_to_map`). This is the same sim/render separation CLAUDE.md mandates — the iso visual layer is a pure projection of the logical grid, and nothing in the sim ever reads a screen coord. (You're doing this; the research just confirms it's the right call.) ([clintbellanger.net iso math](https://clintbellanger.net/articles/isometric_math/), [pikuma](https://pikuma.com/blog/isometric-projection-in-games))
- **Depth sorting:** enable **Y-Sort** on the unit/tile layer (painter's algorithm) for correct occlusion.

---

## 4. Competitive map design (curated vs procedural)

- **Verdict: curated + symmetric.** The map is the dominant balance lever — "Brood War was not balanced by Blizzard changing unit stats, but primarily by map design." Hand-authored, mirror/rotationally symmetric maps guarantee no spawn is positionally doomed; designers place chokepoints/expansions for *intended* tempo. ([TerranCraft](https://terrancraft.com/2019/09/07/the-effects-of-game-design-philosophy-on-map-making/), [Golden Wall post-mortem](https://www.gamedeveloper.com/design/starcraft-2-ladder-map-post-mortem-golden-wall))
- **Procedural is viable only with fairness constraints bolted on:** AoE2's Random Map Scripts give *the same variation to every player* and build symmetric layouts; PSMAGE generates StarCraft maps via Voronoi-region skeletons + symmetry + a fairness fitness score (starting-location distribution, choke symmetry, equal resource access). The pattern: **(1) structural/symmetry pass decides bases+chokes+resources and global validity → (2) tile-detail pass fills cosmetics seamlessly within that skeleton → (3) validation/scoring pass rejects unfair maps.** WFC only does step 2. ([PSMAGE](https://www.researchgate.net/publication/261266936_PSMAGE_Balanced_map_generation_for_StarCraft))
- **For The Long Wake:** your TownPlanner already does structural generation. For competitive, layer a **symmetry/mirroring post-pass + per-spawn equalization** (resource access, choke exposure), all off `SimRng` so it's lockstep-reproducible. For 6p FFA, perfect symmetry is impossible — equalize per-spawn expansion access and choke exposure instead.

---

## 5. Reference-image-to-map (your ridley PoC, generalized)

A secondary capability — good for *variety* or *campaign* maps, not your primary art solution. No one-click tool; you assemble: **image → segment/classify into category regions → downsample to grid → map cell→tile → autotile.**

- **Segmentation SOTA: SAM 3** (Meta, Nov 19 2025) — open-vocabulary "concept" segmentation from a *text noun phrase* ("water", "road", "rooftop"), segments all matching regions at once. This is exactly the "label every region by terrain class" primitive. Use via **`opengeos/segment-geospatial` (SamGeo)** for georeferenced rasters (point/box/text prompt → GeoTIFF/shapefile). ([SAM3](https://ai.meta.com/research/publications/sam-3-segment-anything-with-concepts/), [SamGeo](https://samgeo.gishub.org/))
- **Deterministic baseline for concept art:** **color-quantization** (k-means/median-cut; each quantized color = a terrain class). Trivial Python (`Pillow` + `numpy`), fully reproducible — fits your determinism rules better than ML inference. Best on clean flat-color art; SAM3 for photographic.
- **Real-world maps:** prefer **OpenStreetMap vectors** (already semantically labeled — skip segmentation, rasterize categories onto your grid in a custom script) over raw satellite raster.
- **Determinism note:** keep all of this as an *offline authoring* step (run once, bake the tilemap into the map file). ML/SAM inference is not bit-exact; color-quantize + `SimRng`-seeded placement is. Never in the runtime sim.

---

## 6. Recommended next steps (de-risk before committing)

**Highest-value, do first:** resolve the **projection question** (§TL;DR #3). Decide 4:3-oblique vs 2:1-dimetric *before* producing art, because every tool and rig assumes 2:1, and a wrong projection is the kind of thing that makes everything "not map correct." If reconsidering is feasible, 2:1 dimetric aligns you with the whole ecosystem.

**Then a 1-day render-to-iso spike** (proves or kills the backbone cheaply):
1. Build one Blender iso rig at your *chosen* projection (ortho camera, fixed Sun, RGBA straight-alpha).
2. Render 3–4 ground tiles (a textured plane is enough) + one building (AI-generate via Tripo, or a simple box) + the Normal pass.
3. Drop them into Godot as an iso TileMap + a Sprite2D building, enable a 2D light, and look: do the tiles seat correctly on the grid, do edges meet, does the light wrap the building?
4. If yes — you have your pipeline, and it scales to props/units/characters. If it fights the grid — that's the projection telling you something.

**Parallel cheap win:** keep PixelLab for rapid top-down concepting and Gemini for character reference, but treat them as *concept/reference* feeding the 3D pipeline, not as final-art sources, once render-to-iso is proven.

---

## Source-backed tool index (quick reference)

- **AI tiles (top-down Wang):** PixelLab (MCP) — solved. Iso Wang: nobody, yet.
- **AI iso buildings/props at scale:** Scenario (Flux-Kontext LoRA).
- **AI 3D for render-to-iso:** Tripo (topology, Godot plugin), Rodin/Hyper3D (realism+rights), Meshy (full pipeline), TRELLIS (open-source fidelity).
- **Blender iso rigs:** Create IsoCam, Blender 2D Sprite Studio, Clint Bellanger's render script.
- **Normal maps:** Blender Normal pass (best) → Laigter / Sprite DLight (from 2D, approximate).
- **Map authoring (iso):** Godot built-in TileMapLayer, or Tiled + YATI. Avoid LDtk/Sprite Fusion for iso.
- **Iso autotiling fix:** TileMapDual; tile_bit_tools / Better Terrain for bit setup.
- **WFC in Godot:** AlexeyBond/godot-constraint-solving (GDScript, learns from example), AliasFactory/Godot_Fast_WFC (overlapping mode), DeBroglie (C#, has global/path constraints).
- **Make AI tiles tileable:** Non-Manifold Diffusion, Tiled Diffusion (research, not shipped).
- **Image→map:** SAM3 / SamGeo, QGIS classification, or deterministic color-quantization.
- **Competitive map balance:** curated + symmetric; PSMAGE/Voronoi + fairness scoring if procedural.
