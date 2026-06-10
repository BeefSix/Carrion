# MAP DESIGN — SC1/SC2 study applied to The Long Wake

*Written 2026-06-10 per Matt's directive: study StarCraft map design, then
author three maps — City, Row-home Suburb, Loose Suburb — mixing regular /
lootable / infested buildings. This doc is the study + the three map specs;
the recipes in `scripts/maps/recipes/` implement them.*

---

## 1. What SC maps actually do (the principles that transfer)

Forty years of RTS map design distills to a handful of load-bearing ideas,
all visible in the canonical maps (Lost Temple, Python, Fighting Spirit,
Metalopolis, Daybreak):

1. **Mirrored spawns, asymmetric middle.** Spawn quarters are near-identical
   (fairness); the contested middle is where the interesting asymmetry lives.
   Our lab already PROVED why this matters: the A6 batch measured the
   player-corner Military losing economy viability purely from infested-
   building distribution. Fairness is spawn-local symmetry.

2. **Main → natural → third: the expansion ladder.** Your first expansion
   ("natural") sits behind a defensible choke near the main; the third is
   exposed and contestable. The GAME is the tension of taking progressively
   riskier ground. Our resource = lootable/infested buildings, so the ladder
   is: **safe cluster near spawn → choke-guarded mid cluster → rich exposed
   center**.

3. **Chokepoints size armies.** Ramps and bridges decide how many units
   fight at once — defense favors narrow, offense favors open. Our streets
   ARE the chokes: alley (1 unit), street (squad), boulevard/plaza (army).
   Building footprints are our cliffs.

4. **Rush distance is a balance dial.** Ground distance between mains sets
   how punishing early aggression is. The A6 lab found Tribal's 1.1-minute
   hunter rush dominant — LONGER rush paths are a map-level counter that
   doesn't touch unit stats.

5. **The middle must be worth fighting over.** SC puts watchtowers, gold
   bases, and the shortest attack paths in the center. Ours: the richest
   infested clusters (gold bases that BITE) + the road network's crossing.

6. **High ground / vision asymmetry.** No cliffs in a town — our analogue is
   the NOISE and zombie-flow information layer: dense districts occlude noise
   (building damping) and pool zombies; open ground carries sound. Quiet
   lanes are our "low ground" — safe but slow, visible to whoever watches.

### The Long Wake twist: the third player
Every SC principle gets refracted through the zombies-as-terrain thesis:
- **Infested buildings are gold bases that fight back** — placement = the
  expansion ladder AND the threat map at once.
- **Zombie pooling basins are the unbuildable air space** — open plazas,
  parks, and wide intersections collect wandering hordes (cluster cohesion
  + the steering field). A map drawn with deliberate basins gives hordes
  somewhere to LIVE, so lanes between them stay traversable-but-tense.
- **Regular (no-use) buildings are the sculpting material** — pure collision
  + noise occlusion. They are walls, chokes, and sound baffles. This is the
  new category this pass introduces: most of a city is scenery, and that's
  exactly what makes the lootable minority legible.

---

## 2. The three maps

All three: 192×192 tiles, two mirrored spawn quarters (NW / SE diagonal),
building mix ratios are per-district data (lab-tunable). Mix legend:
R = regular (no use), L = lootable, I = infested.

### Map 1 — "DOWNTOWN" (the city)
*Feel: canyon warfare. Dense commercial grid, narrow alleys, two plazas.*
- **Layout:** Manhattan grid of large commercial/industrial blocks (3-5 tile
  frontage walls of mostly-Regular buildings) cut by a 2-lane avenue cross
  through the center. Two open PLAZAS off-center (the zombie basins). Spawn
  quarters are lower-density office fringe with a guarded street choke into
  the grid (the "natural" = a small commercial cluster one block out).
- **Mix:** fringe 70R/25L/5I → mid blocks 60R/25L/15I → plaza-adjacent
  center 40R/30L/30I (the rich, bitten middle).
- **SC analogue:** Fighting Spirit's safe corners + violent center.
- **Identity:** longest rush distance of the three (anti-rush map); alleys
  make suppression and chokeholds king; noise occlusion everywhere — the
  quiet map where you hear nothing coming.

### Map 2 — "TERRACE ROW" (crowded suburb, row homes)
*Feel: trench lines. Contiguous row-home blocks form WALLS with gaps.*
- **Layout:** long east-west rows of attached homes (Regular, contiguous
  footprints — literal walls) with periodic gap-chokes (a missing house, a
  burned lot). Streets between rows are parallel lanes; crossing lanes only
  at the gaps. Center: a school + strip-mall cluster (civic/commercial
  lootables) around a small park basin. Naturals: the first row-block
  behind each spawn's gap.
- **Mix:** rows 80R/15L/5I → gap blocks 50R/30L/20I → center 35R/35L/30I.
- **SC analogue:** Daybreak's lane discipline — few crossings, every gap a
  named fight.
- **Identity:** medium rush distance; the map plays in LANES — herding a
  horde down a row-lane with the Caller is a battering ram; gaps are where
  walls/turtling pay.

### Map 3 — "ORCHARD SPRAWL" (loose suburb, single homes + driveways)
*Feel: open skirmish country. Detached homes, yards, driveways, sightlines.*
- **Layout:** scattered single homes on large lots (driveway = a 1-tile
  paved stub off the street, yard = grass), loose curving streets, a
  central four-way with a gas station + market cluster. Several open
  fields/parks (big zombie basins). Almost no hard chokes — cover comes
  from individual buildings, not walls.
- **Mix:** outskirts 65R/30L/5I → mid 55R/30L/15I → center cluster
  30R/40L/30I.
- **SC analogue:** Python's open middle — armies meet where they choose;
  map control belongs to mobility and vision.
- **Identity:** shortest rush distance (the aggressive map); hordes roam
  freely between basins so the ecosystem pressure is ambient everywhere;
  kiting/raiding factions feast, turtles suffer.

---

## 3. Implementation: recipe mode for TownPlanner

Authored ≠ hand-placed. Each map is a **recipe** — deterministic district
plans (road skeleton, block templates, per-district building mix) consumed
by TownPlanner in place of its free generation. Same Lootable/building
spawn pipeline downstream, plus the new **Regular building** (Building
subclass: collision + iso body + noise occlusion, no salvage, no actions).
Selection: title screen map picker + `--map=downtown|terrace|orchard` CLI
(procgen remains the default / fourth option).

Mix ratios, basin sizes, and rush distances are all data — the lab measures
them (the A6 corner-asymmetry finding becomes a per-map fairness check:
mirror-match win rates per spawn quarter should be ~50%).
