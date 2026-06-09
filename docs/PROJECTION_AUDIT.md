# Projection + Map-Correctness Audit

*Investigation requested 2026-06-09 to evaluate ART_PIPELINE_RESEARCH.md §TL;DR #3 (the projection flag) and pin down the current rendering pipeline's grid-correctness before any art work goes further. This is **report only** — no projection or rendering changes were made.*

---

## TL;DR

- **Current projection is 4:3 oblique** (`ISO_TILE_W=64`, `ISO_TILE_H=48`, ratio 0.75). Confirmed in `autoloads/IsoView.gd` lines 21-23 with the explanatory comment. This is **not** the 2:1 dimetric (64×32, 0.5) that the entire iso-art tooling ecosystem assumes — including Pixellab, Tiled, every Blender iso rig, Godot's TileMap autotile guides, and the existing tile/character generation pipeline.
- **Grid-correctness is solid.** The logical grid and the rendered iso match exactly: `IsoView.world_to_screen(0,0) = (0,0)` and `IsoView.world_to_screen(TILE_WORLD_PX, 0) = (32, 24)`, which is also where Godot's `TileMapLayer` with `tile_shape = ISOMETRIC` + `tile_size = (64,48)` places cell (1, 0). No half-tile origin offset bug, no drift between sim and render.
- **Sim/render separation is clean.** All gameplay (movement, distances, navigation, fields, win-conditions) operates in world coords. `IsoView` is only ever called at the I/O boundary: render time (sprite offset, z-index, camera) and input time (mouse → world). Auditing the 17 files that touch `IsoView`, every call is on the correct side of the line.
- **Y-Sort is not enabled.** Depth sorting is hand-rolled via `IsoView.z_for(global_position)` → `z_index`, called per-frame on units. Works, but not the Godot-standard way and quietly limits how new sprite hierarchies can be composed.
- **GroundTiles is already using a proper iso TileMapLayer.** `tile_shape = TILE_SHAPE_ISOMETRIC`, `tile_layout = TILE_LAYOUT_DIAMOND_DOWN`, `tile_size = Vector2i(64, 48)`. Ready to receive real per-tile art as soon as the source PNGs are diamond-shaped and the right aspect for the chosen projection.
- **Recommendation: migrate to 2:1 dimetric.** Scope is surprisingly small (≈4 files, mostly constant edits). Today's mismatch is the root cause of "our generated ground tiles look awful" — Pixellab outputs 2:1 iso art and we crop it into a 4:3 frame, distorting every tile by 33% vertically. Migration aligns us with every art tool we're using AND unblocks the ART_PIPELINE_RESEARCH.md §2 render-to-iso (Blender) path. Tradeoff: the camera angle reads slightly less tilted, which was the original "stronger tilt" reason for picking 4:3.

---

## 1. Current Projection — Precise Definition

`autoloads/IsoView.gd`:

```gdscript
const TILE_WORLD_PX = 32.0
const ISO_TILE_W    = 64.0
const ISO_TILE_H    = 48.0      # 4:3 ratio, not the 2:1 standard

func world_to_screen(world_pos, height = 0.0):
    var tile_x = world_pos.x / TILE_WORLD_PX
    var tile_y = world_pos.y / TILE_WORLD_PX
    var screen_x = (tile_x - tile_y) * (ISO_TILE_W * 0.5)
    var screen_y = (tile_x + tile_y) * (ISO_TILE_H * 0.5) - height
    return Vector2(screen_x, screen_y)
```

Implied tile dimensions on screen: **64 wide × 48 tall**. The 0.5/0.5 factors on the projection are correct iso math; the non-standard piece is *what those factors multiply* — namely `ISO_TILE_H=48` instead of 32.

Identity table (proves the math):

| world coord | tile coord | iso screen coord | confirms |
|---|---|---|---|
| (0, 0) | (0, 0) | (0, 0) | origin matches |
| (32, 0) | (1, 0) | (32, 24) | +x in world goes down-right in iso |
| (0, 32) | (0, 1) | (-32, 24) | +y in world goes down-left in iso |
| (32, 32) | (1, 1) | (0, 48) | diagonal advances by full ISO_TILE_H |
| (6144, 6144) | (192, 192) | (0, 9216) | map corner at the bottom of the diamond |

For comparison, **2:1 dimetric** (`ISO_TILE_H=32`) gives identity:

| world coord | iso screen (2:1) | iso screen (4:3, today) |
|---|---|---|
| (32, 0) | (32, **16**) | (32, **24**) |
| (32, 32) | (0, **32**) | (0, **48**) |
| (6144, 6144) | (0, **6144**) | (0, **9216**) |

The full world has 50% more vertical screen span today than it would at 2:1.

## 2. Grid Correctness — Tile/Unit/Building Seat the Logical Grid?

**Yes.** Godot's `TileMapLayer` with `tile_shape = ISOMETRIC` + `tile_layout = TILE_LAYOUT_DIAMOND_DOWN` + `tile_size = Vector2i(64, 48)` projects cell (x, y) to local position `((x-y) * 32, (x+y) * 24)`. That is *exactly* what `IsoView.world_to_screen` produces for world position `(x * 32, y * 32)`. The two coordinate spaces — Godot's TileMap iso and our custom IsoView — agree pixel-for-pixel.

- No half-tile origin offset bug. Both systems put (0, 0) at the same spot.
- No drift between cells and units: units render at `IsoView.world_to_screen(position)` (Unit.gd:240 sprite branch + Unit.gd:522 procedural-draw iso_offset branch). Buildings same (Building.gd:96, plus the four-corner footprint conversion at lines 105-108).
- Walls (`scripts/Wall.gd`) align: their world position projects through `IsoView` like every other entity.
- Ground tiles are placed via `set_cell(Vector2i(x, y), 0, ...)` from a 192×192 byte grid (`GroundTiles.apply_tile_grid`). Godot handles the projection per its iso tile_size, which (as shown above) matches IsoView's math.

**The grid is correct.** The complaint "doesn't map correct" in ART_PIPELINE_RESEARCH.md §TL;DR #3 is *not* about cells landing at wrong screen positions — it's about the projection itself being non-standard, which makes the art-tooling pipeline fight you. See §4.

## 3. Sim/Render Separation — CLAUDE.md Rule #6

> "Sim/render separation: gameplay state must never read from render state (positions are sim state; sprite offsets, iso projection, z-index are render)."

Auditing every IsoView caller:

| File | What it does | Side |
|---|---|---|
| `autoloads/IsoView.gd` | Defines projection | n/a |
| `scripts/Main.gd` | `_center_camera_on_spawn` — projects HQ spawn → iso for camera position | **render** (camera is visual) |
| `scripts/Unit.gd:233` | Per-frame `z_index = IsoView.z_for(global_position)` | **render** (z_index is visual) |
| `scripts/Unit.gd:240` | Sprite child `position = world_to_screen(position) - position` | **render** (sprite offset) |
| `scripts/Unit.gd:522` | Procedural-draw branch computes iso_offset for the same effect | **render** (CanvasItem _draw) |
| `scripts/Building.gd:40` | `z_index = IsoView.z_for(back_corner)` | **render** |
| `scripts/Building.gd:96` | Sprite child offset | **render** |
| `scripts/Building.gd:105-108` | Building footprint corner projection (for drawing the building polygon) | **render** |
| `scripts/Wall.gd:16` | `position = IsoView.world_to_screen(world_pos)` — Wall is a Node2D in iso space because it doesn't move | **render** |
| `scripts/SelectionManager.gd:128` | `IsoView.screen_to_world(get_global_mouse_position())` — mouse → world | **input** (boundary) |
| `scripts/SelectionManager.gd:239` | Same — mouse marquee end → world | **input** |
| `scripts/SelectionManager.gd:282` | Selection hit-test: unit world → iso to compare with mouse iso | **input** |
| `scripts/SelectionManager.gd:379` | Wall placement preview projection | **render** |
| `scripts/maps/TownPlanner.gd:1359-1371` | Uses `IsoView.TILE_WORLD_PX` as a scale constant when converting tile coords to world coords | **sim** ✓ — this is `tile → world`, not a screen projection. Reading a constant, not screen state. |
| `scripts/Shambler.gd`, `scripts/DecayField.gd`, `scripts/NoiseField.gd`, `scripts/Projectile.gd`, `scripts/Corpse.gd`, `scripts/SuppressionField.gd` | Sundry render/input uses | **render** or **input** in every case I sampled |

**Zero sim/render leaks found.** Every IsoView call is on the right side of the boundary. The custom map JSON loader in `Main.gd` (`_install_image_background`) is render-only (Polygon2D + UV). The image-to-map pipeline writes a tile_grid into the sim with no screen-coord pollution.

The one wart: **the camera lives in iso screen space** (`RTSCamera.center_on_world` projects world → iso before assigning camera position; WASD pans iso, not world). That's normal for an iso 2D RTS and is itself a render-side concern — but it does mean the camera bounds in `Main.tscn` (`limit_left=-6500`, `limit_top=-400`, `limit_right=6500`, `limit_bottom=9700`) are hand-tuned for the *current* 4:3 projection. A migration changes those numbers.

## 4. Tile Rendering Path — Ready for Real Art?

**Mostly yes.** `scripts/GroundTiles.gd` is the right shape:

```gdscript
ts.tile_shape  = TileSet.TILE_SHAPE_ISOMETRIC
ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
ts.tile_size   = Vector2i(TILE_W, TILE_H)   # 64×48 today
```

The current `_build_tileset()` programmatically stitches the 11 slot PNGs (`tile_0.png` etc. from `assets/tiles/ground/`) into a single atlas image, applies the diamond mask, and registers each slot as an atlas cell. The PNG loader path (`_load_tile_image`) handles compressed textures, format conversion, and resizing to `TILE_W × TILE_H` — all clean.

What's **wrong for real art today:**

1. **Pixellab generates 2:1 dimetric iso tiles, not 4:3 oblique.** Their `tile_view: top-down` (what we're using now) returns 64×64 diamond-shaped pixel art with the diamond drawn at the standard 2:1 aspect (vertical extent ≈32px inside a 64×64 canvas). We then resize that to 64×48, stretching the diamond vertically by 50%. Result: textures distort, edges don't line up between adjacent cells. This *is* a primary contributor to "the ground tiles look awful" from your last playtest — the art isn't fighting itself, the projection mismatch is fighting the art.
2. **Y-Sort is off.** `Main.tscn` has no `y_sort_enabled` anywhere. Depth-sort is hand-rolled via `IsoView.z_for` → `z_index`. This works for the flat sprites we have today, but adding a per-tile prop layer (trees, lamps, dumpsters) on top of GroundTiles will get awkward because the props need to interleave with units by depth — Godot's automatic Y-sort handles this for free if enabled at the parent node, and the manual z_index path fights that.
3. **No `map_to_local`/`local_to_map` use anywhere.** Sim → render conversion goes through our custom `IsoView.world_to_screen`. That's correct math (and matches Godot's TileMap output), but it means we don't get to use Godot's built-in tile picker for input handling (e.g., "what cell did the mouse hit?" would be one TileMapLayer call instead of the SelectionManager logic). Not a bug; an unused convenience.

What's **right** for real art today:

- The tile atlas atlas-source pattern is correct (one TextureAtlasSource, N atlas cells at (0, i)).
- The diamond mask in `_build_tileset` ensures any source texture is clipped to the iso footprint so neighbor cells don't bleed — this part survives any projection change.
- The `apply_tile_grid` pump is dumb-and-fast — paint cells from a byte array. Real per-tile art has zero impact on this code path.

## 5. The Big Question — Stay 4:3 vs Migrate to 2:1?

### Honest tradeoff

| Axis | 4:3 oblique (today) | 2:1 dimetric (industry std) |
|---|---|---|
| Camera feel | Steeper tilt, more ground plane visible, tall things "lean" less. The reason it was originally picked. Project Zomboid / Stoneshard sit in this range. | Flatter, classic AoE2 / Diablo II feel. Slightly less ground-plane immersion. |
| Pixellab iso tiles | Mismatch: Pixellab outputs 2:1, we stretch to 4:3 → distortion and edge mismatch. | Match: Pixellab output drops in correctly proportioned. |
| Blender render-to-iso (ART_PIPELINE_RESEARCH §2) | Every published rig & tutorial assumes RotX=60° + RotZ=45° = 2:1 dimetric. Using these at 4:3 means hand-tweaking the camera angle for *every* asset render, no source can be reused. | Drop-in compatible with Create IsoCam, Blender 2D Sprite Studio, Bellanger render script. The whole 3D pipeline becomes accessible. |
| Tiled / YATI authoring | Tiled supports any iso aspect but its terrain/wang tooling is built around 2:1. | Drop-in. |
| TileMapDual (the iso autotile fix) | ~Works at any aspect since you supply the tiles; example tilesets assume 2:1. | Drop-in. |
| Existing character sprites (Shambler v3, Rifleman v5, Looter v3, HG v2, Brawler/Brute v1) | "low top-down" character renders don't depend on tile aspect — they're standalone 3/4-view sprites that look correct over any iso ground. | Same. No impact. |
| Existing ground tile PNGs | Designed-for-2:1 art forced into 4:3 frame — they distort. Today's "ugly tiles" outcome. | Use the same PNGs, no resize. Probably look immediately better. |
| Camera bounds in Main.tscn | Tuned to 4:3. | Need to be re-tuned (the world iso diamond is shorter). |
| Z_DEPTH_SCALE constant | Tuned to 4:3 world depth range. | Re-tune (the world is shorter, less depth range, finer resolution available). |

### Recommendation: **Migrate to 2:1 dimetric.**

Reasons in order:
1. **It's the single highest-leverage fix in the project right now.** ART_PIPELINE_RESEARCH.md called this out as the root cause of "doesn't map correct"; this audit confirms the underlying grid is correct, but the projection-vs-tooling mismatch is. Until that's fixed, every tile art attempt fights it.
2. **Scope is small.** Concrete file list and line counts below.
3. **It's the right time.** You've explicitly accepted that the ground tiles need rework and don't yet have a wide art catalog locked to the 4:3 aspect. The only "asset" coupled to 4:3 is the camera bounds tuning, which gets re-tuned in any case.
4. **It unblocks ART_PIPELINE_RESEARCH §2** (the render-to-iso Blender pipeline, which is the report's main long-term recommendation).

The cost: the camera angle will read less tilted. If "stronger tilt" is a deliberate aesthetic you want to preserve, the workaround is **render assets at a steeper camera angle** (Blender camera RotX=50°-ish instead of 60°) and ship them onto a flat 2:1 tile grid — best of both worlds. This is exactly what Project Zomboid does: their tiles are 2:1 dimetric grid, but their ART is rendered at a steeper angle to give that "more vertical lean" feel.

## 6. Migration Plan (if 2:1 approved)

Concrete scope: **~4 files, mostly constant edits.** Estimate: 1-2 hours including playtest tuning.

| File | Change |
|---|---|
| `autoloads/IsoView.gd` | `ISO_TILE_H = 48` → `32`. Update the comment block (lines 12-19) to describe 2:1 dimetric. Z_DEPTH_SCALE may want a retune from 8 → 6 to fit the now-shorter world depth range; pick by running headless and checking `IsoView.z_for(MAP_SIZE * 2)` stays within ±4000. |
| `scripts/GroundTiles.gd` | `const TILE_H := 48` → `32`. Atlas image height auto-follows. Existing PNG load + diamond mask logic works as-is at the new aspect. |
| `scenes/Main.tscn` | Camera bounds `limit_top`, `limit_bottom` need to be re-tuned for the now-shorter iso world (was tuned for 9216 max vertical extent; will be 6144). Recommended quick math: set `limit_top = -400`, `limit_bottom = 6500`. Field-test from the spawn corner and adjust. |
| (anywhere a literal `48` matches a tile height) | Quick grep: `ripgrep '\b48\b' --type-add 'gd:*.gd' --type gd` and audit hits in `scripts/`. Not a known site — the only tile-height literal I'd expect is GroundTiles' constant — but verify before commit. |

What does **NOT** change:

- Every gameplay system (movement, range checks, navigation, fields, win-conditions, AI, replay/checksum, command bus). All world-coord. Sim is projection-agnostic.
- All character sprites. Pixellab "low top-down" renders are independent of tile aspect.
- The image-to-map pipeline (TownPlanner, custom map JSON loader). Operates entirely in world/tile coords.
- The CommandBus / ReplayRecorder / SimChecksum harness from earlier today. Doesn't touch projection.
- Pixellab generation prompts and Pro-mode character pipeline.

Optional follow-up commit (NOT in scope of the projection migration, mention only):

- **Switch to Godot Y-Sort.** Set `y_sort_enabled = true` on Main (or a dedicated YSort node parenting Ground + Units + Buildings + Props). Remove the manual `z_index = IsoView.z_for(...)` calls in Unit/Building/Wall. Godot will sort by `global_position.y` automatically. This is a small but meaningful cleanup that lets you drop in per-tile prop sprites and have them interleave with units for free. ~2 files, 30 minutes.

Incremental rollout: yes. The migration can land in a single commit that flips IsoView + GroundTiles + camera bounds simultaneously; the game keeps working at every step because no other code depends on the specific aspect ratio. There's no "big-bang" required.

## 7. Quick Wins Regardless of the Projection Decision

These are net-positive even if you decide to stay 4:3:

1. **Enable Y-Sort on the main scene** (the optional follow-up above). Decouples future prop / decal / decoration sprites from manual z_index discipline. ~30 min.
2. **Replace the procedural diamond mask in `GroundTiles._build_tileset` with a single shared mask Image** built once, then `blit_rect_mask`'d into each atlas cell. Same visual result, ~5x faster atlas build. Costs ~10 lines of code.
3. **Add an `assert(IsoView.world_to_screen(IsoView.screen_to_world(p)) == p)`** test (or even just a `_ready` check in IsoView when running under `--check-only`) so any future projection math change can't silently break the inverse. ~5 lines.
4. **Use `TileMapLayer.local_to_map(local_mouse_pos)` for tile hit-tests in `GroundTiles.get_tile_type_at`** instead of the current world-to-tile integer math. Self-documenting and won't drift if the projection changes again. ~3 lines.

## Files I read for this audit

- `ART_PIPELINE_RESEARCH.md`
- `CLAUDE.md` (sim/render separation rule, determinism rules)
- `autoloads/IsoView.gd`
- `scripts/GroundTiles.gd`
- `scripts/Unit.gd` (iso offset + z_index logic)
- `scripts/Building.gd` (iso offset, z, footprint projection)
- `scripts/Wall.gd`
- `scripts/RTSCamera.gd`
- `scripts/SelectionManager.gd` (input boundary)
- `scripts/Main.gd` (camera centering + custom-map loader)
- `scripts/maps/TownPlanner.gd` (tile-coord-to-world conversion)
- `scenes/Main.tscn` (Y-sort check, camera bounds)
- All 17 files that touch IsoView (sampled)

**Awaiting decision on §5 + §6 before any code changes.**
