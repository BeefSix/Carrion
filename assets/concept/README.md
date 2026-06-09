# Faction style anchors

The three canonical faction reference images. These are the **style references** the PixelLab art pipeline feeds into every unit/asset generation for that faction (see docs/ART_ASSET_LIST.md and DESIGN_MASTER.md §10.5). The PixelLab run is mostly pointless without them — they're what keeps each faction's roster visually coherent.

Drop the three images here with these EXACT filenames:

- **`military_anchor.png`** — the modern soldier: combat helmet, plate carrier, assault rifle + sidearm, olive/coyote fatigues, bearded VISIBLE face, unit patch. (Face visible = identity intact; manufactured mil-gear.)
- **`survivor_anchor.png`** — the hooded scavenger: full improvised gas mask (round filter), layered earth-toned scavenged clothing, chest rig/pouches, improvised weapon, face HIDDEN. (Face hidden = anonymous survival; scavenged civilian scraps.)
- **`tribal_anchor.png`** — the feral ritualist: dreadlocks, scarified bare torso, bone/antler ornaments, animal skull worn, hide wraps, barefoot, spear + bow. (Face bare but transformed; bone-and-hide, made from the dead.)

Generative rule (DESIGN_MASTER §10.5): **face = identity, material = relationship to the old world.** Every derived unit must answer "how do this unit's face and kit express its faction?"
