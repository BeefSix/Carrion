"""
Image-to-Map PoC Pipeline for Carrion v2.

After v1 failed (per-pixel color classification produced near-uniform regions
- the source image is overall low-contrast with high pixel-level noise),
this version uses TILE-LEVEL TEXTURE analysis instead:

  - Compute grayscale luminance and Sobel edge magnitude.
  - Block-average to 192x192 tile grid.
  - Classify per tile via combined luminance + edge-density thresholds.

Pipeline:
  1. Load image.
  2. Tile-level texture statistics (luminance mean, edge density, edge variance).
  3. Per-tile classification (developed / open / road / water / athletic).
  4. Major building detection: zones with high contiguous edge density.
  5. Output ridley_data.json + ridley_mask.png for inspection.
  6. Hand-curated landmark buildings added in landmarks.py (next step).
"""

from PIL import Image
import numpy as np
import json
import os
from scipy.ndimage import sobel, gaussian_filter, label, find_objects, binary_opening, binary_closing

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SOURCE_IMG = os.path.join(ROOT, "assets", "maps", "ridley.png")
OUT_MASK = os.path.join(ROOT, "assets", "maps", "ridley_mask.png")
OUT_DATA = os.path.join(ROOT, "assets", "maps", "ridley_data.json")

WORLD_SIZE = 6144
TILE_SIZE_WORLD = 32
TILE_COUNT = 192

# Tile categories
CAT_OPEN = 0       # open ground - default walkable
CAT_ROAD = 1       # road/path
CAT_PARKING = 2    # paved lot - walkable but not part of road network
CAT_BUILDING = 3   # building footprint
CAT_ATHLETIC = 4   # sports field
CAT_WATER = 5      # impassable
CAT_RAIL = 6

CAT_NAMES = ["open", "road", "parking", "building", "athletic", "water", "rail"]
CAT_COLORS = {
    CAT_OPEN:     (139, 110, 76),
    CAT_ROAD:     (40, 40, 50),
    CAT_PARKING:  (110, 110, 120),
    CAT_BUILDING: (180, 60, 50),
    CAT_ATHLETIC: (80, 140, 70),
    CAT_WATER:    (40, 80, 100),
    CAT_RAIL:     (140, 100, 60),
}


def compute_tile_stats(img_arr):
    """For each tile in a 192x192 grid, compute mean luminance, edge density,
    and R/G/B mean. Returns dict of (H, W) arrays."""
    H, W = img_arr.shape[:2]
    block = W / TILE_COUNT  # ~10.67

    # Grayscale luminance
    r = img_arr[..., 0].astype(np.float32)
    g = img_arr[..., 1].astype(np.float32)
    b = img_arr[..., 2].astype(np.float32)
    gray = 0.299 * r + 0.587 * g + 0.114 * b

    # Edge magnitude via Sobel
    sx = sobel(gray, axis=0)
    sy = sobel(gray, axis=1)
    edges = np.hypot(sx, sy)

    # Block-average to 192x192
    def block_mean(a):
        out = np.zeros((TILE_COUNT, TILE_COUNT), dtype=np.float32)
        for ty in range(TILE_COUNT):
            y0 = int(ty * block)
            y1 = max(int((ty + 1) * block), y0 + 1)
            for tx in range(TILE_COUNT):
                x0 = int(tx * block)
                x1 = max(int((tx + 1) * block), x0 + 1)
                out[ty, tx] = a[y0:y1, x0:x1].mean()
        return out

    return {
        "luma": block_mean(gray),
        "edges": block_mean(edges),
        "r": block_mean(r),
        "g": block_mean(g),
        "b": block_mean(b),
    }


def classify_tiles(stats):
    """Per-tile classification from texture + color features."""
    luma = stats["luma"]
    edges = stats["edges"]
    r = stats["r"]
    g = stats["g"]
    b = stats["b"]

    out = np.full((TILE_COUNT, TILE_COUNT), CAT_OPEN, dtype=np.uint8)

    # Water: very dark + low edges + cool tint. Looking at samples, water in the
    # source averages ~30 luma in bottom-left.
    water = (luma < 40) & (edges < 10) & (b > r * 0.9)
    out[water] = CAT_WATER

    # Athletic green pitch: VERY distinct green hue (tight thresholds - the
    # source image's overall tan tint makes weak-green detection false-fire
    # on too many tiles). Restrict to clearly green-dominant tiles.
    athletic_green = (g > r + 14) & (g > b + 14) & (g > 75)
    # Running track: VERY distinct red-orange hue
    athletic_red = (r > g + 25) & (r > b + 35) & (r > 110)
    out[athletic_green | athletic_red] = CAT_ATHLETIC

    # Road: low edges AND lower luminance than typical ground (in this image
    # roads are darker than yards). Tighten with a context check below.
    road = (edges < 18) & (luma < 70) & (out == CAT_OPEN)
    out[road] = CAT_ROAD

    # Parking lot: low edges + mid luminance (lighter than road, more uniform
    # than building areas). Lots are usually paved with car-spot stripes but
    # the texture is more uniform than residential blocks.
    parking = (edges < 22) & (luma >= 70) & (luma < 100) & (out == CAT_OPEN)
    out[parking] = CAT_PARKING

    # Buildings: high edge density. Residential blocks have lots of small
    # rooftop edges; commercial/institutional buildings have long strong edges.
    # Use a moderately high threshold so we don't flag everything.
    building = (edges >= 28) & (out == CAT_OPEN)
    out[building] = CAT_BUILDING

    return out


def cleanup_tiles(tiles):
    """Morphological cleanup at tile level - close small holes, remove specks."""
    # Building blobs: close small gaps, remove isolated tiles
    building_mask = (tiles == CAT_BUILDING)
    building_mask = binary_closing(building_mask, iterations=1)
    building_mask = binary_opening(building_mask, iterations=1)
    tiles_out = tiles.copy()
    # Wherever cleanup removed a tile, fall back to road if the tile was originally
    # interpreted as building - the area is probably mixed road+building tiles.
    became_open = (tiles == CAT_BUILDING) & ~building_mask
    became_building = (tiles != CAT_BUILDING) & building_mask
    tiles_out[became_open] = CAT_OPEN
    tiles_out[became_building] = CAT_BUILDING
    return tiles_out


def extract_buildings_from_tiles(tiles):
    """Connected-components on the tile-level building mask. Returns building list."""
    building_mask = (tiles == CAT_BUILDING).astype(np.uint8)
    labeled, n = label(building_mask)
    slices = find_objects(labeled)
    print(f"  Tile-blob building count: {n}")

    buildings = []
    for i, sl in enumerate(slices):
        if sl is None:
            continue
        y_slice, x_slice = sl
        h_tiles = y_slice.stop - y_slice.start
        w_tiles = x_slice.stop - x_slice.start
        area_tiles = h_tiles * w_tiles

        # Filter: at least 2 tiles in area, not larger than 1/8 of map
        if area_tiles < 2 or area_tiles > 600:
            continue

        # World coords
        cy_tile = (y_slice.start + y_slice.stop) / 2.0
        cx_tile = (x_slice.start + x_slice.stop) / 2.0
        cx_world = cx_tile * TILE_SIZE_WORLD
        cy_world = cy_tile * TILE_SIZE_WORLD
        w_world = w_tiles * TILE_SIZE_WORLD
        h_world = h_tiles * TILE_SIZE_WORLD

        # Type inference from size
        if area_tiles < 4:
            ntype = "residential"
        elif area_tiles < 20:
            ntype = "commercial"
        else:
            ntype = "industrial"

        buildings.append({
            "id": i,
            "pos": [round(cx_world, 1), round(cy_world, 1)],
            "size": [round(w_world, 1), round(h_world, 1)],
            "type": ntype,
            "tile_area": int(area_tiles),
        })

    print(f"  Buildings extracted: {len(buildings)}")
    return buildings


def write_mask_image(tiles, path):
    """Render tile grid as a tile-resolution mask image (192x192 upsampled)."""
    H, W = tiles.shape
    out = np.zeros((H, W, 3), dtype=np.uint8)
    for cat, color in CAT_COLORS.items():
        out[tiles == cat] = color
    # Upscale to source resolution for easier comparison.
    Image.fromarray(out, mode="RGB").resize((2048, 2048), Image.NEAREST).save(path)
    print(f"  Wrote mask: {path}")


def main():
    print(f"Loading {SOURCE_IMG}")
    img = Image.open(SOURCE_IMG).convert("RGB")
    arr = np.array(img)
    print(f"  Image: {img.size}")

    print("Stage 2: tile-level texture statistics")
    stats = compute_tile_stats(arr)
    print(f"  luma mean range: {stats['luma'].min():.1f} - {stats['luma'].max():.1f}")
    print(f"  edges mean range: {stats['edges'].min():.1f} - {stats['edges'].max():.1f}")

    print("Stage 3: per-tile classification")
    tiles = classify_tiles(stats)
    tcats, tcounts = np.unique(tiles, return_counts=True)
    for c, n in zip(tcats, tcounts):
        name = CAT_NAMES[c] if c < len(CAT_NAMES) else f"cat{c}"
        print(f"  {name:10s}: {n:5d} tiles ({100.0 * n / tiles.size:.1f}%)")

    print("Stage 3b: morphological cleanup")
    tiles = cleanup_tiles(tiles)

    print("Stage 4: extracting building blobs from tile mask")
    buildings = extract_buildings_from_tiles(tiles)

    print("Writing tile mask for inspection")
    write_mask_image(tiles, OUT_MASK)

    print(f"Writing {OUT_DATA}")
    data = {
        "source_image": "res://assets/maps/ridley.png",
        "world_size": WORLD_SIZE,
        "tile_count": TILE_COUNT,
        "tile_size_world": TILE_SIZE_WORLD,
        "buildings": buildings,
        "tile_grid": ["".join(str(int(v)) for v in row) for row in tiles],
    }
    with open(OUT_DATA, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  {len(buildings)} buildings + 192x192 tile grid")
    print("Done.")


if __name__ == "__main__":
    main()
