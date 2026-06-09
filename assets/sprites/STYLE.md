# Carrion sprite style spec

**Locked 2026-06-09.** This is the project standard for all current and
future unit sprites — Hunter, Drifter, Shaman, Walker, future faction
units — until and unless explicitly amended.

## Direction

- **Dark, muted, realistic.** No bright cartoonish palettes; no soft
  pastels. Think weathered field equipment under overcast light.
- **Clean silhouette legibility at game scale.** Pose + outline must
  read at the iso zoom level the camera sits at; ornament is welcome
  but never at the cost of silhouette.
- **Family palette: dark olive / charcoal / muted earth tones** for
  Military; **leathery grey + faded street clothes** for zombies;
  Tribal + Survivor palettes designed when those land. Avoid pure
  saturated red/blue/green except as accent.

## Pipeline (Pixellab MCP)

- **Mode**: `pro` (20 generations, 8 directions, AI-reference-based).
  `standard` mode was rejected in 2026-06-09 review as too cartoonish.
- **Size**: 64 px character (gives ~92 x 92 canvas with the
  ~40 % padding Pixellab adds for animation overhead).
- **View**: `low top-down`.
- **Outline / shading / detail**: ignored in pro mode; rely on the
  text prompt and Pixellab's pro-mode reference engine.

## Prompt shape

Lead with the character role + faction, then push hard on the
weathered / realistic descriptors. Always include:

1. Role + faction (e.g. "Military rifleman", "scavenger soldier",
   "desiccated civilian zombie").
2. Specific weapon + carry pose, NOT generic ("belt-fed M60 style
   heavy machine gun at hip with folded bipod", not just "machine
   gunner").
3. Specific clothing items grounded in the design palette ("dark
   olive-drab combat uniform with weathered tactical gear", not
   "soldier outfit").
4. Posture / stance ("hunched forward shambling", "wide stable combat
   stance").
5. Closer: `"dark muted realistic palette, weathered post-apocalyptic
   <faction>"`. The trailing realistic-palette phrasing is what
   pushes Pixellab away from the cartoonish default.

## Reference characters (canon style anchors)

When generating new units, reference the most recent successful
character in the same family for stylistic continuity:

- **Military**: Rifleman v5 / Looter v3 / HeavyGunner v2 (regen'd
  2026-06-09 in pro mode at 64 px).
- **Zombies**: Shambler v3 (Pixellab id `d40ae599-d881-4b96-85e4-1ae0e7c2dc4e`).

Update this list when newer generations are accepted as canon.

## Anti-patterns (do NOT do)

- "Cute" / "stylized" / "chibi" / "cartoon" descriptors.
- Bright saturated color anchors (yellow, magenta, neon).
- Generic "soldier" / "zombie" / "scavenger" with no specifics — the
  pro-mode reference engine produces stock results without anchors.
- Tatters + bandages on every faction. Zombies are decayed civilians,
  NOT a uniform aesthetic.
