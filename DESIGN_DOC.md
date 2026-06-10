# CARRION — Technical Design Document v0.1

> **⚠️ HISTORICAL — SUPERSEDED. Do NOT implement from this file.** This early design doc has been superseded by **DESIGN_MASTER.md** (the design source of truth) and the codename change to **The Long Wake**. Kept only for provenance/early reasoning. Where this conflicts with DESIGN_MASTER.md, DESIGN_MASTER wins, always.

**Author note (in-character):** This is written as a working technical spec, the kind that goes into the doc repo before a vertical slice. It assumes familiarity with RTS systems vocabulary (DPS, supply, build orders, micro/macro split) and uses Blizzard-lineage conventions for stat presentation. Numbers given are *anchor values* — the math is internally consistent but every value is subject to playtest tuning. Where I'm making a design call to fill in a gap that wasn't yet decided in the design conversations, I flag it with **[DESIGN CALL]**.

---

## 1. Document Purpose & Scope

This document specifies the mechanical systems, balance math, and implementation targets for **Carrion**, an asymmetric three-faction RTS set in a long-collapsed zombie apocalypse. It is the technical companion to the design-pillars document and assumes the design conversations have been read. This doc does not re-litigate design philosophy; it defines the math that makes that philosophy operate.

**Scope:**
- Map, resource, and economy specifications
- Full unit stat tables with DPS derivations
- Zombie AI, spawn, and aggro math
- Decay system formulas
- Noise propagation math
- Day/night cycle and Eclipse trigger math
- Doctrine path numeric shifts
- Win condition trigger thresholds
- Match pacing targets
- Implementation notes

**Out of scope (separate documents):**
- Lore and world-building
- Art direction specifications
- Sound design
- Campaign / single-player content
- Monetization

---

## 2. Executive Summary

Carrion is a **45–60 minute** asymmetric RTS for 1v1 and 1v1v1, designed around longer matches than the SC2 standard (15–25 min) to accommodate territory-transformation mechanics that don't reach their full expression in shorter sessions.

Three factions operate three fundamentally different economies:
- **Military:** active gathering, noise-generating, decay-producing, ammo-dependent
- **Survivors:** passive farming + stealth scavenging + map-based recruitment
- **Tribal:** zombie-immune gathering + corpse harvesting + ritual production

Each faction has two **Doctrine** commitments locked in during minutes 8–15 that rotate the matchup triangle. Each unit has two **Unit Upgrades** that target the two opposing factions. The combined strategy space is approximately 3 × 2 × 8 × 2 = ~96 distinct unit/path configurations, enough to support a competitive metagame.

The map is a **third actor** — zombies spawn from buildings, respond to noise, drift toward decay, and physically transform the play space over the course of a match. Three ground states (Tainted / Clean / Decayed) define the strategic geography. Asymmetric win conditions (network reach / territory percentage / zombie mass) replace standard elimination.

---

## 3. Design Principles (Numeric Targets)

These are the constraints all systems are designed against:

| Principle | Target |
|---|---|
| Match length (median) | 45 min |
| Match length (long tail, 90th percentile) | 75 min |
| Match length (short tail, 10th percentile) | 25 min |
| Time-to-first-engagement | 4–8 min |
| Doctrine commit window | 8:00–15:00 |
| Maximum APM ceiling (skill cap) | 250 |
| Minimum APM floor (playability) | 40 |
| Worker-equivalent count at saturation | 6–12 per faction |
| Population cap (organic units) | 150–250 depending on faction |
| Distinct unit types per faction | 7–9 |
| Buildings per match (player + neutral) | 80–150 |
| Active zombies on map (steady-state) | 200–400 |
| Active zombies during Eclipse | 600–1200 |
| Target frame rate (1080p, mid-spec) | 60 FPS sustained |

---

## 4. Map Specifications

### 4.1 Dimensions

**Standard 1v1 map:** 192 × 192 tiles (SC2 reference: 128–160 tiles)
**Standard 1v1v1 map:** 224 × 224 tiles
**Tile size:** 1.0 game unit (SC2-equivalent)
**Pathing granularity:** 0.25 tile (sub-tile pathing for fluid movement)

The dimensions are deliberately ~50% larger than SC2 standard. Three reasons: (1) longer matches require more strategic space, (2) territory mechanics need room to express, (3) the third actor (zombies) needs map area to populate without crowding player units.

### 4.2 Starting Positions

Players start at random map-edge positions, minimum 80 tiles apart in 1v1, minimum 60 tiles apart in 1v1v1. Each player gets an **initial cleared zone**: 12-tile radius around starting position, no zombies, all buildings unlooted.

**[DESIGN CALL]** Random starting positions (not symmetric mirror positions like SC2) because the asymmetric factions break symmetric balance anyway. Map balance is achieved through resource node distribution and *zombie density* rather than positional mirroring.

### 4.3 Building Distribution

Lootable buildings are distributed across the map by **neighborhood type**, each with a pre-apocalypse identity that determines spawn types and loot:

| Neighborhood Type | Building Count | Zombie Spawn Profile | Loot Profile |
|---|---|---|---|
| Residential | 30–40% of map | Shamblers, civilians | Mixed low-tier (food, water, scrap) |
| Commercial | 15–20% | Shamblers + occasional Runners | Mid-tier (food, scrap, occasional ammo) |
| Industrial | 10–15% | Brutes more common, fewer total | Scrap-heavy, occasional ammo |
| Medical | 5–10% | Medic zombies, Brutes from morgues | Supplies, occasional ammo |
| Security (police, military checkpoints) | 5–10% | Soldier/cop zombies | Ammo-heavy |
| Civic (schools, government) | 5–10% | Mixed, some Runners | Mid-tier mixed |
| Wild zones (parks, undeveloped) | 5–15% | Low density, Runners more common | Minimal loot, contested by tribal |

A balanced 1v1 map should target ~100–120 total lootable buildings. Resource density per zone is **risk-correlated**: security zones have the most ammo but produce the toughest enhanced returns; medical zones have brutes; wild zones are tribal-favorable.

### 4.4 Fog of War

Standard RTS fog-of-war model (3 states: unexplored / explored / visible). **Vision ranges** are unit-specific (see unit tables). At night, vision range reduced by 40% across all units (see §10).

---

## 5. Resource Economy

### 5.1 Resources

Five resources, asymmetrically used across factions:

| Resource | Military | Survivor | Tribal | Source |
|---|---|---|---|---|
| **Ammo** | Primary | Limited use | None | Looted from buildings, harvested from soldier/cop zombies |
| **Food** | Moderate (rations) | Primary | Moderate | Farms (survivors), looted, harvested |
| **Water** | Moderate | Primary | Moderate | Water collection (survivors), looted |
| **Scrap** | Required for vehicles | Required for fortifications | Limited | Harvested from any zombie corpse, looted from industrial |
| **Ritual Material** | None | None | Primary (Shamans, conversions, tames) | Harvested by tribal Hunters/Beastmasters from zombie kills |

### 5.2 Resource Gather Rates

Anchor values for sustained gather rates, assuming optimal play and unmolested operation:

**Military Looter:**
- Cost: 50 ammo + 25 food
- Build time: 18 sec
- HP: 60, light armor
- Move speed: 3.0
- Loot per trip: 80 resource (split based on building type)
- Trip time: 30 sec (round trip to nearby building)
- Effective rate: **160 resource/min per Looter**
- **Noise generated per loot: 25** (pulls zombies)
- Soft cap on simultaneous Looters: ~8 (more than this and they're competing for routes and pulling collective zombie pressure)
- **Effective faction income at saturation: ~1280 resource/min** (8 Looters × 160), of which ~70% is ammo at security districts, ~50% mixed elsewhere

**Survivor Scout:**
- Cost: 50 food + 25 water
- Build time: 25 sec
- HP: 40, no armor
- Move speed: 3.0
- Loot per trip: 100 resource
- Trip time: 40 sec (slower because sneaking)
- Effective rate: **150 resource/min per Scout**
- Noise generated: **0** (sneak gathering)
- Hard cap: **4 Scouts** per Safehouse, maximum 2 Safehouses → **8 Scouts max**
- **Effective Scout income at cap: 1200 resource/min**
- Supplemented by passive Farms (10 food/min each) and Water Collection (8 water/min each)
- At saturation (8 Scouts + 6 Farms + 6 Water): ~1200 looted + 60 food/min + 48 water/min

**Tribal Walker:**
- Cost: 30 ritual material + 25 food
- Build time: 20 sec
- HP: 30, no armor
- Move speed: 2.5
- Loot per trip: 70 resource
- Trip time: 30 sec
- Effective rate: **140 resource/min per Walker**
- Noise generated: **0**
- Special: ignored by all zombie types (Shamblers, Runners, Brutes pass through)
- No hard cap, soft cap ~12 (route saturation)
- **Effective income at saturation: 1680 resource/min**
- Plus Hunter/Beastmaster harvest: 5–15 ritual material per zombie killed nearby

### 5.3 Economic Curves

Steady-state income curves at minutes 5, 15, 30, 45 of a standard match:

| Minute | Military | Survivor | Tribal |
|---|---|---|---|
| 5:00 | 400/min (2–3 Looters) | 300/min (2 Scouts + 2 Farms) | 280/min (2 Walkers) |
| 15:00 | 960/min (6 Looters) | 750/min (4 Scouts + 4 Farms) | 700/min (5 Walkers) |
| 30:00 | 1280/min (8 Looters, soft cap) | 1100/min (6 Scouts + 6 Farms + Water) | 1400/min (10 Walkers) |
| 45:00 | 1280/min (cap reached) | 1300/min (full saturation + rescues) | 1680/min (12 Walkers) |

**Implication:** Tribal has the highest steady-state income but the slowest ramp. Military hits its ceiling fastest but plateaus. Survivors curve smoothly upward and overtake military around minute 30 due to passive infrastructure. This curve shape is the reason matchups shift over the course of a match — economic timings determine when each faction is at its relative peak.

### 5.4 Population System

Population cap (organic units only) varies by faction:

| Faction | Base Cap | Per-Structure Gain | Maximum |
|---|---|---|---|
| Military | 30 (Command Post) | +10 per Barracks (×4), +5 Officer | **200** |
| Survivors | 30 (Settlement Hub) | +15 per Safehouse (×2), +1–3 per rescued NPC | **250** |
| Tribal | 30 (Camp) | +15 per Ritual Site (×3), +5 Witch Doctor | **150 organic + 200 tamed zombies** (separate cap) |

**Implication:** Survivors can field the largest organic force (250) because their identity is community. Tribal has the smallest organic roster (150) but supplements with tamed packs (up to 200 zombies under tribal control), giving them the largest *total* force but with most of it being zombie units that operate under different rules.

---

## 6. Faction Production Math

### 6.1 Building Cost & Build Time Anchors

All build times reference a standard 1.0× speed; matches can be played at 1.0× (standard), 1.25× (fast), or 1.5× (faster) similar to SC2 game speed options.

**Military:**

| Structure | Cost | Build Time | Function |
|---|---|---|---|
| Command Post (HQ) | Starting | — | Trains Officer; doctrine independent |
| Barracks | 200 ammo + 100 scrap | 50 sec | Riflemen, Shotgunners, Heavy Gunners |
| Motor Pool | 300 ammo + 200 scrap | 65 sec | Humvees, APCs |
| Field Hospital | 150 ammo + 150 food | 45 sec | Combat Medics; Field Sanitation upgrade |
| Armory | 250 ammo + 100 scrap | 50 sec | Demolitions; **Doctrine commit structure** |
| Comms Tower | 200 ammo + 100 scrap | 40 sec | Officer call-in abilities |
| Watchtower | 100 ammo + 50 scrap | 30 sec | Static defense |
| Forward Operating Base (Heavy Doctrine) | 500 ammo + 300 scrap | 90 sec | Upgraded HQ; double decay radius |

**Survivors:**

| Structure | Cost | Build Time | Function |
|---|---|---|---|
| Settlement Hub (HQ) | Starting | — | Trains Leader; **Doctrine commit structure** |
| Workshop | 150 food + 100 water + 100 scrap | 50 sec | Engineers, Brawlers, traps, walls |
| Greenhouse / Farm | 100 food + 50 water + 50 scrap | 40 sec | +10 food/min |
| Water Collection | 50 food + 100 scrap | 35 sec | +8 water/min |
| Safehouse | 150 food + 100 water + 150 scrap | 60 sec | Scouts; rescued NPC conversion |
| Radio Shack | 100 food + 150 scrap | 45 sec | +25% rescue event spawn rate; +5 noise/sec ambient |
| Garage | 200 food + 200 scrap | 55 sec | Drivers, vehicle repair |
| Militia Hall (Militia Doctrine) | 250 food + 150 water + 200 scrap | 70 sec | Direct Marksman/Medic production |
| Watchtower / Lookout post | 100 food + 100 scrap | 30 sec | Static defense; Sanctuary upgrade unlocks Lookout sniper position |

**Tribal:**

| Structure | Cost | Build Time | Function |
|---|---|---|---|
| Camp (HQ) | Starting | — | Trains Chieftain; **Doctrine commit structure** |
| Hunting Lodge | 150 ritual + 100 food | 45 sec | Hunters, Berserkers |
| Ritual Site | 200 ritual + 100 food | 50 sec | Shamans, Witch Doctors; built on/near infested buildings |
| Pack Pit | 200 ritual + 150 food | 55 sec | Beastmasters; pack cap upgrades |
| Bone Yard | 100 ritual + 100 food | 40 sec | Auto-harvests ritual material from zombies killed within 15 tiles |
| Totem | 75 ritual + 50 food | 30 sec | Pulls zombies in 20-tile radius |
| Conversion Shrine (Whisper unlock primary, available to all) | 300 ritual + 200 food | 75 sec | Convert enemy elite corpses |
| Spawn Pit (Siege Doctrine) | 250 ritual + 150 food | 60 sec | Direct spawn against enemy structures |

### 6.2 Build Order Reference (Opening Build)

A standard 8-minute opening for each faction, similar to SC1/SC2 build order conventions:

**Military "Quick Looter Rush":**
- 0:00 Start with Command Post, 2 starting Riflemen, 100 ammo + 50 food
- 0:18 Looter #1 (50 ammo + 25 food → cost paid; 18 sec build)
- 0:36 Looter #2
- 1:00 Barracks (200 ammo + 100 scrap; need scrap from first loot trips)
- 2:30 Barracks complete; queue 2 Riflemen
- 3:00 Looter #3 (now have 3 Looters generating ~480/min)
- 4:00 Field Hospital → Combat Medic
- 5:30 Armory (doctrine commit available from here)
- 7:00 Officer training begins
- 8:00 Looter #4–5, first significant engagement possible

**Survivor "Settle and Farm":**
- 0:00 Start with Settlement Hub, 2 starting Brawlers, Engineer, 150 food/water/scrap
- 0:25 Scout #1 (build at Settlement Hub, requires Safehouse for replacement scouts later)
- 0:40 Greenhouse begun by Engineer (40 sec)
- 1:20 Greenhouse complete, +10 food/min ticks
- 1:30 Safehouse begun (60 sec)
- 2:30 Safehouse complete, Scout #2 can be queued
- 2:55 Scout #2 begins
- 3:20 Scout #2 complete
- 4:00 Workshop begun
- 4:50 Workshop complete, Engineer #2 + first walls begin
- 6:00 Second Greenhouse, second Water Collection
- 7:00 Radio Shack (start triggering rescue events)
- 8:00 Roster: 2 Brawlers, 2 Engineers, 2 Scouts, beginning to fortify

**Tribal "Walk the Wilds":**
- 0:00 Start with Camp, 2 starting Hunters, Walker, 100 ritual + 100 food
- 0:20 Walker #2 (30 ritual + 25 food)
- 0:40 Walker #3 (need to be queueing fast for ritual income)
- 1:00 Hunting Lodge begun
- 1:45 Lodge complete; Berserker #1 (50 ritual + 50 food)
- 2:30 Ritual Site begun
- 3:20 Ritual Site complete; Shaman queued (40 sec)
- 4:00 Shaman complete; first force-spawn at infested building (5 sec channel + 25 ritual = 4 shamblers spawn)
- 5:00 Pack Pit begun
- 6:00 Beastmaster queued; first tames possible
- 7:00 Bone Yard near contested areas
- 8:00 Roster: 2 Hunters, 1 Berserker, 1 Shaman, 1 Beastmaster, 4 Walkers, ~6 spawned shamblers under indirect influence

These openings are anchor templates; metagame will evolve variants.

---

## 7. Unit Stat Tables

All stats use SC2-style conventions. **DPS** values are calculated as `damage / attack_period`. **Range** values are in tiles. **Speed** is in tiles/sec.

### 7.1 Military Units

| Unit | HP | Armor | DPS | Range | Speed | Cost | Build | Supply | Noise/shot |
|---|---|---|---|---|---|---|---|---|---|
| Looter | 60 | 0 | 8 | 4 | 3.0 | 50A/25F | 18s | 1 | 8 |
| Rifleman | 70 | 0 | 12 | 6 | 2.5 | 50A/25F | 25s | 2 | 10 |
| Shotgunner | 80 | 1 | 25 | 3 | 2.8 | 75A/25F/25Sc | 28s | 2 | 15 |
| Heavy Gunner | 100 | 1 | 35 (area) | 5 | 2.0 | 125A/50F/50Sc | 40s | 3 | 50/sec |
| Combat Medic | 60 | 0 | — | 4 (heal) | 2.5 | 50A/50F/50Sc | 30s | 2 | 0 (heal) |
| Demolitions | 70 | 0 | 60/grenade (4s CD) | 5 | 2.3 | 75A/75F/50Sc | 35s | 3 | 100/grenade |
| Humvee | 250 | 2 | 18 | 6 | 4.5 | 200A/100Sc | 50s | 4 | 20/sec moving |
| APC | 500 | 3 | 12 | 5 | 3.5 | 350A/200Sc | 75s | 6 (transports 6) | 30/sec moving |
| **Officer** (hero) | 200 | 1 | 20 | 6 | 3.0 | 100A/100F/50Sc | 60s | 4 | 10 |
| **Ghost Squad** (Silent unlock) | 90 | 0 | 18 (suppressed) | 7 | 3.2 | 150A/75F/50Sc | 50s | 4 | 3 |
| **Main Battle Tank** (Heavy unlock) | 800 | 5 | 80 (siege) | 9 | 2.5 | 600A/400Sc | 120s | 8 | 150/shot |

### 7.2 Survivor Units

| Unit | HP | Armor | DPS | Range | Speed | Cost | Build | Supply | Noise/shot |
|---|---|---|---|---|---|---|---|---|---|
| Scout | 40 | 0 | 5 | 4 (silenced) | 3.0 | 50F/25W | 25s | 2 | 1 |
| Engineer | 60 | 0 | 8 (melee) | 1 | 2.5 | 50F/25W/25Sc | 25s | 2 | 0 |
| Marksman | 50 | 0 | 18 | 8 (silenced) | 2.5 | 100F/50W/50Sc | 35s | 3 | 2 |
| Brawler | 80 | 1 | 22 (melee) | 1 | 3.0 | 50F/50W/25Sc | 25s | 2 | 0 |
| Medic | 50 | 0 | — | 4 (heal) | 2.5 | 75F/50W/50Sc | 30s | 2 | 0 |
| Driver | 50 | 0 | 10 | — (in vehicle) | 2.5 | 75F/50W | 25s | 2 | variable |
| **Leader** (hero) | 180 | 1 | 15 | 6 (silenced) | 2.8 | 100F/100W/50Sc | 60s | 4 | 2 |
| **Veteran** (Militia unlock) | 90 | 1 | 16 | 7 | 2.6 | 125F/75W/75Sc | 45s | 3 | 8 |
| **Lookout** (Sanctuary unlock) | 60 | 0 | 22 | 10 (immobile) | 0 | 100F/50W/100Sc | 40s | 1 | 2 |

### 7.3 Tribal Units

| Unit | HP | Armor | DPS | Range | Speed | Cost | Build | Supply | Noise/shot |
|---|---|---|---|---|---|---|---|---|---|
| Walker | 30 | 0 | — | — | 2.5 | 30R/25F | 20s | 1 | 0 |
| Hunter | 50 | 0 | 14 | 7 (silent) | 3.0 | 50R/25F | 30s | 2 | 1 |
| Berserker | 90 | 1 | 25 (melee) | 1 | 4.0 | 50R/50F | 25s | 2 | 0 |
| Shaman | 60 | 0 | — | — (ritual) | 2.3 | 100R/75F | 40s | 3 | 0 |
| Beastmaster | 80 | 1 | 15 | 4 | 2.8 | 100R/100F | 35s | 3 | 0 |
| Herder | 60 | 0 | 8 | 5 | 3.0 | 75R/50F | 30s | 2 | 0 |
| Witch Doctor | 50 | 0 | — | 5 (heal/buff) | 2.5 | 75R/75F | 35s | 3 | 0 |
| **Chieftain** (hero) | 200 | 1 | 18 | 5 | 3.0 | 100R/100F | 60s | 4 | 0 |

### 7.4 Zombie Units (Neutral / Tamed)

| Unit | HP | Armor | DPS | Range | Speed | Notes |
|---|---|---|---|---|---|---|
| Shambler | 40 | 0 | 8 (melee) | 1 | 1.5 | Baseline spawn |
| Runner | 60 | 0 | 12 (melee) | 1 | 3.5 | From recent kills |
| Brute | 200 | 2 | 30 (melee, AoE) | 1.5 | 1.5 | Rare; tameable |
| Enhanced Heavy Gunner Z | 150 | 2 | 20 (area) | 4 | 2.0 | Returns with gear |
| Enhanced Demolitions Z | 100 | 0 | 80 on-death AoE | — | 2.5 | Explodes on contact/death |
| Enhanced Marksman Z | 70 | 0 | 16 | 6 | 2.8 | Faster, ranged |
| **Suicide Bomber** (Heavy Gunner conversion) | 80 | 0 | 200 AoE on contact | — | 3.0 | One-shot, devastating |
| **Plague Carrier** (Medic conversion) | 100 | 1 | — (heal) 8/sec | 5 | 2.0 | Heals nearby zombies |
| **Walking Bomb** (Demolitions conversion) | 120 | 0 | 350 AoE on death | — | 2.8 | Massive |
| **Champion** (Officer conversion) | 180 | 2 | 20 | 4 | 2.5 | Aura: +25% damage to nearby zombies |
| **Stalker** (Marksman conversion) | 90 | 0 | 22 | 7 | 3.5 | Silent, picks off isolated units |

---

## 8. Combat Engagement Math

Worked examples for canonical engagements. All assume even ground, no upgrades, no terrain effects, and full focus fire.

### 8.1 Anti-Brute: 4 Riflemen vs 1 Brute

- Rifleman group HP: 4 × 70 = 280 | Combined DPS: 48
- Brute HP: 200 | DPS: 30
- Time to kill Brute: 200 / 48 = **4.17 sec**
- Brute damage dealt before death: 30 × 4.17 = **125 damage**
- Distributed across 4 Riflemen (assume some kiting): ~1 Rifleman lost
- **Cost ratio:** 4 Riflemen (200A + 100F) vs 1 Brute (~200 ritual material to tame)
- **Result:** Even engagement; military edge if proper kiting micro applied

### 8.2 Wall Breaking: Demolitions vs Walls

Wall HP values:
- Standard Wall: 250 HP
- Reinforced Wall (Sanctuary tier 1): 500 HP
- Reinforced Wall (Sanctuary tier 2): 750 HP

Demolitions grenade: 60 damage, ×1.5 structure multiplier = **90 effective damage to walls**

| Wall Type | Grenades to Break | Time (4s CD) |
|---|---|---|
| Standard | 3 | 12 sec |
| Reinforced T1 | 6 | 24 sec |
| Reinforced T2 | 9 | 36 sec |

With Shaped Charges upgrade (×2 structure damage = 180/grenade):

| Wall Type | Grenades to Break | Time |
|---|---|---|
| Standard | 2 | 8 sec |
| Reinforced T1 | 3 | 12 sec |
| Reinforced T2 | 5 | 20 sec |

With Main Battle Tank (Heavy Doctrine): 80 DPS at 9 range, ×1.5 structure = 120 DPS to walls. Cracks reinforced T2 in **6.25 sec** with no closing required.

### 8.3 Horde vs Settlement

Standard horde event (250 noise threshold): 25 mixed zombies arrive over 30 sec.

- 25 Shamblers: combined HP 1000, combined DPS at melee 200
- Defended by: 4 Marksmen (200 HP, 72 DPS at 8 range) + 2 Brawlers (160 HP, 44 DPS melee) + 6 standard walls (1500 HP total)

Pre-melee phase (zombies approaching, ranged fire):
- Marksmen kill rate: 72 / 8 = 9 zombies/sec... wait, that's wrong; 72 DPS against 40 HP shamblers = 1.8 kills/sec
- Travel time across firing range (8 tiles at 1.5 speed): 5.3 sec
- Kills before melee contact: 1.8 × 5.3 = ~9–10 zombies killed pre-melee
- Wall contact: 15–16 Shamblers reach walls
- Wall durability: 1500 HP / (15 zombies × 8 DPS) = 12.5 sec to break first wall section
- During wall attack, Brawlers + Marksmen continue dealing: 116 DPS
- Remaining wall-attacking zombies (15) take 15 × 40 / 116 = ~5 sec to clear
- **Result:** Settlement survives this horde with manageable wall damage. The defense holds.

Same engagement during night (zombie +25% speed, +100% spawn rate during horde): horde becomes ~50 zombies, defense math flips toward marginal loss without reinforcement.

### 8.4 Engagement: Military Squad vs Tribal Berserker Wave

- Military squad: 4 Riflemen + 1 Heavy Gunner + 1 Combat Medic = 470 HP, 95+ DPS
- Tribal wave: 6 Berserkers = 540 HP, 150 DPS (melee only)

Closing math (Berserker speed 4.0, Heavy Gunner range 5):
- Heavy Gunner kills rate against Berserkers: 35 / 90 = 0.39 kills/sec
- Time for Berserkers to close 5 tiles at speed 4.0: 1.25 sec
- Pre-melee Berserker kills: 0.39 × 1.25 = ~0.5 Berserker
- Rifleman pre-melee kills (range 6, additional sec): 60 / 90 = 0.67, plus first 1.25 = additional 1 Berserker total
- Berserkers reaching melee: 5
- Melee phase: 5 Berserkers (450 HP) vs military squad (~430 HP, accounting for damage taken)
- Berserker DPS at melee: 125 | Military DPS in melee range: 95
- Berserkers win melee race: military dies in 430/125 = 3.4 sec; Berserkers take 450/95 = 4.7 sec
- **Result:** Tribal wins by ~1.3 sec margin; military squad wiped, 1–2 Berserkers survive

Counter-strategy: Combat Medic healing keeps squad alive longer; Demolitions grenades kill Berserkers pre-contact (1 grenade kills 2 Berserkers in tight formation). With +1 Demolitions, the engagement flips:
- Pre-melee Berserker kills with Demolitions: 3–4 (2 grenades over 4 sec at 60 damage AoE)
- Berserkers reaching melee: 2–3
- Easily handled by military squad

**Implication:** Demolitions is *critical* for military vs tribal. Without it, melee waves overrun military squads despite military's ranged advantage. This justifies Demolitions as a core unit, not a niche pick.

### 8.5 Conversion Cost-Benefit (Tribal vs Military)

Tribal Conversion Shrine ritual: 150 ritual material + 8 sec channel + corpse retrieval.

Suicide Bomber from Heavy Gunner corpse:
- Cost: 150 ritual + 8 sec
- Effect: 200 AoE damage on contact
- Equivalent to: ~3 Demolitions grenades worth of damage, single-use
- Comparison: Tribal could spend 150 ritual on Berserkers (3 Berserkers at 50R each, 75 supply combined) which deal ~600 cumulative damage over their lifetime

**Verdict:** Suicide Bomber is *not* purely efficient — it's situational. It's most valuable for cracking specific high-value targets (a clustered Marksman position, an Officer, a Settlement Hub door). Tribal players should convert opportunistically, not always.

This is intentional balance: conversion should feel like a *moment*, not the default play.

---

## 9. Zombie System Math

### 9.1 Baseline Spawn Mechanics

Every infested building has a **spawn timer** and **type table**:

```
spawn_interval = base_interval × (1 - density_modifier) × (night_modifier) × (decay_modifier)

base_interval = 60 sec (one zombie per minute baseline)
density_modifier = 0.3 if active player units within 20 tiles, else 0
night_modifier = 0.5 at night (twice as fast), 1.0 by day
decay_modifier = 1.0 - (local_decay / 200) — at 100 decay, spawn rate doubles
```

Type roll on spawn:
- Default: 80% Shambler, 18% Runner, 2% Brute (modified by neighborhood)
- Hospital: 60% Shambler, 25% Medic-Z, 15% Brute (from morgues)
- Security: 70% Shambler, 25% Soldier-Z, 5% Runner
- etc.

Total active zombies on map are capped at ~400 baseline (performance ceiling). When at cap, spawns pause until count drops.

### 9.2 Zombie AI (Behavior Tree Summary)

Top-level priority (highest first):

1. **Marked target** (Shaman ability, lasts 30 sec): zombie paths directly toward marked unit
2. **Noise source** (highest noise point within 50 tiles): paths toward noise
3. **Visible non-tribal target** (within 12 tile vision): paths toward target
4. **Decay attractor** (Decayed tile within 25 tiles): drifts toward decay
5. **Idle wander** (random direction shift every 10 sec)

Tribal units are *not* on the visible target list. Tamed zombies follow Beastmaster and inherit Beastmaster's priority list.

### 9.3 Enhanced Return Math

When a unit dies, it has a probability and timer for becoming an enhanced zombie:

```
return_probability = base_rate × class_modifier × time_decay
base_rate = 1.0 (100% by default)
class_modifier: 1.0 for combat units, 0.5 for non-combat (Engineers, Drivers), 0.0 for tribal (they're tamed)
time_decay = 1.0 if not cremated within 90 sec, 0.0 if cremated

return_delay = 30 sec + (HP_max / 5) sec
  → Rifleman returns in 30 + 14 = 44 sec
  → Heavy Gunner returns in 30 + 20 = 50 sec
  → Officer returns in 30 + 40 = 70 sec (heroes take longer)
```

Cremation action: 4 sec channel on corpse by any combat unit, costs 5 scrap. Prevents return entirely.

### 9.4 Aggro / Noise Math

Noise generation by source (cumulative within 50-tile radius, decays at 5 noise/sec):

| Source | Noise per Event |
|---|---|
| Suppressed weapon | 1–3 |
| Pistol shot | 5 |
| Rifle shot | 10 |
| Shotgun shot | 15 |
| Heavy Gunner firing | 50/sec while firing |
| Grenade explosion | 100 |
| Tank shot | 150 |
| Vehicle (moving) | 20–30/sec |
| Loot action (military) | 25 (one-time per loot) |
| Wall destruction | 50 |
| Building destruction | 100 |

Cumulative noise within a 50-tile radius is tracked as a heat value. Thresholds:

| Cumulative Noise | Effect |
|---|---|
| 0–99 | Normal spawn rate |
| 100–249 | Small horde event: 10 Shamblers spawn from map edge, path to noise center |
| 250–499 | Medium horde event: 25 mixed zombies |
| 500–999 | Large horde event: 50 mixed zombies, including 2–3 Brutes |
| 1000+ | Catastrophic event: 75+ zombies, dense Brute composition |

Noise decays globally at 5/sec, so a Heavy Gunner firing continuously generates noise at a net rate of 45/sec (50 generated - 5 decay) and triggers a small horde in about 2.5 sec of sustained fire.

### 9.5 Decay Math

Decay accumulates around military structures while active:

```
decay_rate_per_tile = 0.1 × structure_factor × (1 - sanitation_modifier)
structure_factor = 1.0 for Command Post, 0.5 for Watchtower, 2.0 for FOB (Heavy Doctrine)
sanitation_modifier = 0.6 if Field Sanitation active, 0 otherwise
```

Decay radius:
- Initial: 4 tiles around structure
- Expansion: +0.5 tiles per minute of active operation
- Maximum: 12 tiles per structure

Effects of decay on terrain:

| Decay Level (per tile) | Effect |
|---|---|
| 0–25 | Visible discoloration, no mechanical effect |
| 26–50 | Spawn rate +25% in tile, slight zombie attraction |
| 51–75 | Spawn rate +50%, Runner chance +10%, light corruption |
| 76–100 | Spawn rate +100%, Brute chance +5%, heavy corruption |
| 100+ | Spawn rate +150%, **persistent** (doesn't decay back without active cleanup) |

When a military structure is destroyed or abandoned, decay continues to grow for 60 sec at half rate, then stabilizes. Survivor Engineer sanitation: 5 decay reduction/sec, costs 2 scrap/sec, must remain stationary.

This is the formal model of the design conversation about military "trashing the ground." Numbers are tuned so a single Heavy Doctrine FOB operating for 10 minutes creates a 12-tile-radius decay zone that becomes a permanent tribal-favorable spawn site if not cleaned.

---

## 10. Day/Night Cycle & Eclipse

### 10.1 Cycle Length

| Phase | Duration | Effects |
|---|---|---|
| Day | 8 min real time | Standard spawn rates, full vision |
| Dusk transition | 30 sec | Lighting shifts, vision starts dropping |
| Night | 4 min real time | Spawn ×2, zombie speed ×1.25, vision ×0.6, noise propagation radius ×1.5 |
| Dawn transition | 30 sec | Lighting normalizes |

Total cycle: ~13 min. Standard 45-min match contains 3.5 cycles (3 full days, 3 full nights, plus partial final phase).

### 10.2 Eclipse Trigger

Eclipse meter is global, fills based on cumulative noise generated by all players across the match:

```
eclipse_meter = sum(noise_events_all_players) - (match_duration × 2)
threshold = 5000
```

When meter reaches 5000, Eclipse begins automatically at the next nightfall (so players have warning between meter fill and event start).

Eclipse duration: 8 min (replaces what would have been the next day phase entirely).

### 10.3 Eclipse Effects

During Eclipse:
- Zombie spawn rate ×5
- Spawn type table shifts: 50% Shambler, 35% Runner, 15% Brute
- Vision range ×0.4
- Noise propagation radius ×2.0
- Tribal force-spawn cost halved
- Conversion Shrine channel time halved
- Decay accumulation paused (the world is too active to decay further)
- Map-wide ambient horde events every 2 min (50+ zombies move across map in patterns)

After Eclipse ends, 15-min cooldown before another Eclipse can build.

### 10.4 Eclipse Strategic Implications

Eclipse fundamentally inverts the matchup triangle for its duration:
- Tribal: massively advantaged (cheap rituals, free conversions, more material to harvest)
- Military: massively disadvantaged (more aggro, harder to operate, decay paused so they can't restart sanitation)
- Survivors: heavily challenged (settlements under constant pressure) but their fortification investment pays off if it holds

Smart military play **avoids triggering Eclipse**. Heavy Doctrine players almost certainly trigger it within 30 min (their noise output is too high to suppress). Silent Doctrine players might never trigger it. Tribal players actively *try* to make others trigger it by baiting fights in noisy zones.

---

## 11. Doctrine Path Math

Doctrines are committed at the faction's HQ-tier structure between minutes 8:00 and 15:00. Commit is **irreversible** for the match. Each doctrine applies modifiers across the entire faction.

### 11.1 Military Doctrines

**Silent Doctrine (anti-Tribal):**

| Stat | Modifier |
|---|---|
| Damage (all units) | ×0.75 |
| Noise generation | ×0.25 |
| Decay rate per structure | ×0.5 |
| Build time (all units) | ×1.20 |
| Unlocks | Ghost Squad, Field Sanitation upgrade |

**Heavy Doctrine (anti-Survivor):**

| Stat | Modifier |
|---|---|
| Damage (all units) | ×1.20 |
| Noise generation | ×1.50 |
| Decay rate per structure | ×1.50 |
| Structure damage (all weapons) | ×2.0 |
| Unlocks | Main Battle Tank, FOB |

### 11.2 Survivor Doctrines

**Militia Doctrine (anti-Military):**

| Stat | Modifier |
|---|---|
| Combat unit damage | ×1.15 |
| Marksman build time | ×0.5 (built directly at Militia Hall) |
| Rescue event rate | ×0.6 |
| Stealth gather (Scout noise) | +5 per loot |
| Unlocks | Militia Hall, Veteran unit |

**Sanctuary Doctrine (anti-Tribal):**

| Stat | Modifier |
|---|---|
| Wall HP | ×2.0 |
| Engineer build speed | ×1.3 |
| Combat unit damage | ×0.9 |
| Rescue event rate | ×1.25 |
| Unlocks | Reinforced Walls T2, Lookout |

### 11.3 Tribal Doctrines

**Siege Doctrine (anti-Survivor):**

| Stat | Modifier |
|---|---|
| Brute tame cost | ×0.6 |
| Brute HP | ×1.5 |
| Berserker melee damage | ×1.2 |
| Map control (Herder/Totem) | ×0.7 |
| Unlocks | Wall Breaker (siege Brute), Spawn Pit |

**Whisper Doctrine (anti-Military):**

| Stat | Modifier |
|---|---|
| Force-spawn cost | ×0.75 |
| Tamed pack cap | ×1.5 |
| Conversion channel time | ×0.7 |
| Combat unit damage | ×0.85 |
| Unlocks | Conversion Shrine (full tier), Voice of the Dead |

### 11.4 Matchup Matrix Examples

Sample matchup states after doctrine commit:

| Military | Survivor | Tribal | Predicted Edge |
|---|---|---|---|
| Silent | Militia | Whisper | Survivor moderate (Militia damage advantage holds against Silent's reduced damage) |
| Heavy | Sanctuary | Siege | Survivor heavy advantage (Sanctuary walls vs Heavy = race, but Tribal Siege is occupied trying to break Survivor too) |
| Silent | Sanctuary | Whisper | Stalemate spiral (everyone defensive) |
| Heavy | Militia | Siege | Bloodbath, fastest match resolution (everyone aggressive) |
| Silent | Sanctuary | Siege | Tribal squeezed (anti-Survivor commit, but Silent military doesn't feed them) |

Match outcome depends heavily on doctrine timing (who commits first reveals their hand) and reading. Scouting is mechanically incentivized.

---

## 12. Unit Upgrades (Sample Specification)

Each unit has 2 mutually-exclusive upgrades available, one targeting each opposing faction. Upgrades are committed per-unit-instance (not globally), so a faction can field mixed upgrade states.

Full list omitted from this version for length; representative samples:

### 12.1 Military Rifleman

| Upgrade | Cost | Effect |
|---|---|---|
| **Suppressor Kit** (vs Tribal) | 25A/15Sc per unit | Noise generated ×0.1; range ×0.85 |
| **AP Rounds** (vs Survivor) | 25A/25Sc per unit | Damage ×1.25 vs armored targets and walls |

### 12.2 Military Demolitions

| Upgrade | Cost | Effect |
|---|---|---|
| **Incendiaries** (vs Tribal) | 50A/30Sc per unit | Grenades cremate corpses in AoE; +20 damage to enhanced zombies |
| **Shaped Charges** (vs Survivor) | 50A/30Sc per unit | Structure damage ×2.0 |

### 12.3 Survivor Marksman

| Upgrade | Cost | Effect |
|---|---|---|
| **Long-Range Scope** (vs Military) | 50F/25W/25Sc per unit | Range +2 (to 10); damage ×1.1 |
| **Shaman Hunter** (vs Tribal) | 50F/25W/25Sc per unit | Damage ×1.5 vs channeling units; interrupts rituals on hit |

### 12.4 Tribal Shaman

| Upgrade | Cost | Effect |
|---|---|---|
| **Crawler Spawns** (vs Survivor) | 75R/50F per Shaman | Spawned shamblers fit through 1-tile wall gaps; speed +0.5 |
| **Rapid Ritual** (vs Military) | 75R/50F per Shaman | Force-spawn channel time ×0.5; cost +25% per spawn |

Full upgrade table: approximately 48 unique upgrades across 24 unit types × 2 opposing faction targets. Implementation should defer the full set until base-game balance is stable; ship initial release with 1 upgrade per unit, then expand in patches.

---

## 13. Win Condition Triggers

Each faction has an asymmetric primary win condition. **Headquarters elimination** (Command Post, Settlement Hub, or Camp destroyed) is a universal secondary win condition.

### 13.1 Military Win: Network Reach

Military wins by controlling the map's traversal infrastructure.

**Definition:** The map contains 8–12 designated **road junctions** placed at strategic intersections. Each junction has a 4-tile capture radius. A junction is "controlled" by a faction when:
- A military unit (or ally — there are no allies, but mechanically: any military unit) is within 4 tiles
- The junction has been "secured" (10-second channel by military Looter or combat unit)
- No enemy unit is within 8 tiles

Network reach is calculated as: percentage of map area within a 20-tile radius of any controlled junction.

**Trigger threshold:** Military controls junctions whose combined coverage exceeds **60% of map area** for **60 sec continuous**.

This makes military's win condition feel like *infrastructure occupation*, not territorial conquest. They don't need to clear the map — they need to own the routes.

### 13.2 Survivor Win: Territory Owned

Survivor wins by accumulating fortified or cleared territory.

**Definition:** A tile is "survivor-owned" if:
- It's within 15 tiles of a survivor-controlled structure, AND
- The path from the structure to the tile is contiguous (not blocked by enemy walls or hostile-controlled buildings)
- The tile is "clean" (no decay, no zombie spawns active)

Territory percentage = (owned tiles / total map tiles) × 100.

**Trigger threshold:** Survivor owns **50% of map area** for **90 sec continuous**.

The 90-second window matters — it gives opponents time to launch a disruptive attack. Survivor doesn't just instantly win on the second they hit 50%; they have to *hold* it under pressure.

### 13.3 Tribal Win: Horde Mass

Tribal wins by sustaining a massive zombie population on the map.

**Definition:** Total active zombies on the map (Shamblers + Runners + Brutes + enhanced returns + tamed pack zombies — everything) above a threshold.

**Trigger threshold:** **800+ zombies on map** for **90 sec continuous**.

Note that the normal map cap is 400 zombies (performance). This is *raised* during a tribal win attempt as the engine prioritizes spawning over other simulation overhead. Effectively the tribal player has to push the map into a state where it's *barely playable* — which is the thematic point.

### 13.4 Secondary Win: HQ Elimination

Any faction wins by destroying both other factions' HQ structures.

In 1v1v1, this is the most common actual ending — usually one faction reaches their primary objective before being eliminated, but elimination is the resolution when primaries stall.

In 1v1, primary win conditions are scaled (e.g., territory thresholds drop to 40% for survivor since there's no third faction siphoning area).

---

## 14. Match Pacing Targets

Designed match arc for a standard 45-minute game:

| Time | Phase | Expected State |
|---|---|---|
| 0:00–5:00 | Opening | Initial workers, first units, scouting begins |
| 5:00–10:00 | Build-out | Tech structures, first engagements possible |
| 8:00–15:00 | Doctrine commit window | Players reveal strategic identity |
| 10:00–20:00 | Expansion | Second base / settlement expansion / horde corridor establishment |
| 20:00–30:00 | First confrontations | Sustained raids, territory contested |
| 30:00–40:00 | Strategic resolution | Win conditions actively pursued, defenses tested |
| 40:00–60:00 | Endgame | One faction approaches victory or stalemate breaks into HQ elimination |

Day/night cycle alignment:
- Day 1: 0:00–8:00
- Night 1: 8:00–12:00 (first major pressure event)
- Day 2: 12:30–20:30
- Night 2: 21:00–25:00 (eclipse triggerable if noise high)
- Day 3: 25:30–33:30
- Night 3: 34:00–38:00 (eclipse high probability)
- Day 4: 38:30–46:30 (most matches resolve before/during this)

---

## 15. Implementation Notes

### 15.1 Engine Recommendation

**Godot 4.x** (3D or 2D) is the recommended engine for a prototype-to-production path. Justifications:

- Open source, no licensing concerns
- Scripting language (GDScript) well-supported by AI-assisted development
- Smaller surface area than Unity for solo/small-team development
- Native support for both 2D and 3D
- Built-in pathfinding (NavMesh) sufficient for unit counts up to ~600 active agents
- Acceptable performance for the unit counts and zombie populations described

**Alternatives considered:**
- **Unity:** more powerful but more overhead; switch to Unity only if specific features (asset store ecosystem, console deployment) are required
- **Unreal:** overkill for this project; physics and rendering pipelines are oversized
- **Custom (web):** sufficient for prototype but ceiling-limited for production

### 15.2 Networking Architecture

Lockstep deterministic networking (the SC1/SC2/AoE2 model) is recommended. Justifications:

- Low bandwidth (only inputs are transmitted, not state)
- Excellent for RTS with high unit counts
- Replay support trivial (replay = recorded input stream)
- Tournament-grade integrity

Tradeoffs:
- All players must run identical simulation (rules out platform variation)
- Desyncs are debugging nightmares (mitigated by deterministic math libraries)
- Late-joiners and disconnects are hard to handle gracefully

Target: 60Hz simulation, 15Hz network tick. Maximum concurrent units across all players + zombies: ~1500.

### 15.3 Performance Ceilings

| System | Active Agent Cap | Notes |
|---|---|---|
| Zombies (baseline) | 400 | Performance constraint |
| Zombies (Eclipse) | 800 | Simulation prioritizes spawn |
| Zombies (Tribal win attempt) | 1200 | Engine ceiling |
| Player units (per faction) | 250 | Population cap enforced |
| Total active agents | ~1500 | Combined ceiling |
| Active structures | 200 | Combined across all factions |
| Particle effects (combat) | 500 | Visual-only, can be culled |

### 15.4 AI Behavior (Zombie Crowd Simulation)

Zombies don't use full pathfinding for every agent (too expensive at 400+). Recommended approach:

- **Flow field** generated periodically (every 2 sec) for major attractors (noise sources, marked targets, decay centers)
- Individual zombies follow the flow field with small random noise
- Pathfinding only invoked when a zombie hits a wall or impassable terrain (local A*)
- Tamed zombies use full pathfinding (they're under player command and need precision)

This is similar to how *They Are Billions* handles 20,000+ zombies on screen. We don't need that many, but the technique scales down well.

### 15.5 Save/Load and Replay

Lockstep determinism enables replays as input streams. Save files should serialize:
- Random seed
- All player input events (timestamped)
- Match configuration (map, factions, rules)

Reconstruction at load time is deterministic from these inputs. This also enables a *time scrubbing* replay viewer, which is invaluable for balance analysis and competitive scene.

---

## 16. Known Balance Risks & Mitigations

These are the design risks I'd flag for early playtesting attention.

### 16.1 Tribal Snowball

**Risk:** Tribal has high steady-state income and benefits from all other players' actions. If they survive the early game uncontested, they may snowball uncatchable economic advantage.

**Mitigation candidates:**
- Tribal's slow tech curve already mitigates (no early aggression option)
- Whisper Doctrine should remain anti-combat to prevent doubling down
- Tribal HQ (Camp) should be the most vulnerable HQ type (low HP, no defensive structures intrinsically)
- Consider: tribal cannot trigger their own win condition during Eclipse (Eclipse must be triggered by others' noise, not tribal-generated mass)

### 16.2 Military Suicide Burn

**Risk:** Heavy Doctrine military may discover that the optimal play is to ignore decay entirely, win-or-lose in 25 minutes, and refuse to engage the long game.

**Mitigation candidates:**
- Heavy Doctrine balanced against this *intentionally* — short-match aggressive is a legitimate strategy
- The matchup *should* have a clear "win window" for Heavy military; if they miss it, they should lose
- Survivors with Sanctuary should hard-counter this; tune wall HP so a competent survivor can hold against optimal Heavy push for 20+ minutes

### 16.3 Survivor Fortification Lock

**Risk:** Sanctuary survivors with optimal walls and farms become impenetrable, leading to stalemates.

**Mitigation candidates:**
- Demolitions and Tanks should always be able to crack walls *eventually*
- Survivor economy depends on Farms which are *outside* their walls (can't farm indoors); these are raidable
- Rescue events occur at random map locations, forcing survivors to leave their walls
- Hard win condition timer: any faction holding their win condition for >60 sec must commit to it (no stalling)

### 16.4 Eclipse Camping

**Risk:** Tribal player intentionally feeds noise to opponents to trigger Eclipse repeatedly.

**Mitigation candidates:**
- Eclipse cooldown (15 min) limits frequency
- Eclipse is hostile to *everyone* including tribal's actual unit control (their tamed packs scatter under the chaos)
- Eclipse meter visible to all players, allowing counter-play

### 16.5 1v1v1 Kingmaking

**Risk:** In 1v1v1, two trailing factions may collaborate to eliminate the leader, then resolve their own conflict. This is the classic 3-player FFA problem.

**Mitigation candidates:**
- Asymmetric win conditions reduce direct competition (factions aren't always racing for the same thing)
- Predation cycle creates partial-overlap incentives (military and survivor share interest in cleared zones; harder to fully ally)
- Late-game balance should favor the player who *almost* won, not always punish them
- No formal alliance system; cooperation is always implicit and unstable

---

## 17. SC1/SC2 Lineage

What we're borrowing from Blizzard's RTS heritage:

- **Hard counters:** every unit has clear counters; no rock-paper-scissors is *fully* even
- **Tech tiers:** building dependencies create predictable timings
- **Macro/micro split:** economy and combat are simultaneous skill demands
- **Population cap:** strategic resource that prevents endless army expansion
- **Build orders:** memorizable opening patterns that experts internalize
- **Replay-driven competitive scene:** lockstep determinism for tournament integrity
- **Asymmetric factions:** each faction is a different *game*, not a different *army*

What we're diverging from:

- **Match length:** 45 min target vs SC2's 15–25 min standard
- **Map as static board:** Carrion's map *transforms* during play (decay, cleared zones, horde flows)
- **Symmetric maps:** Carrion uses asymmetric maps with random starting positions
- **Single resource flow per faction:** Carrion has 5 resources with asymmetric needs
- **Elimination as primary win:** Carrion uses asymmetric primary objectives
- **2-faction matchups:** Carrion is balanced primarily around 1v1v1 (3-faction) play
- **Neutral terrain:** Carrion's "neutral" zombie actor is an active participant
- **Doctrine commits:** mid-match strategic identity shifts; SC2 has no equivalent
- **Cremation/corpse mechanics:** new layer of post-engagement play

The unifying philosophical departure: **the map is a participant, not a board.** Every system in Carrion engages with this. Decay grows, cleared zones spread, hordes drift, demographics shift. SC2 maps are chessboards; Carrion maps are ecosystems. This is the design call that everything else flows from.

---

## 18. Open Questions Requiring Playtest

These are the values I'd consider most uncertain in the current spec:

1. **Match length 45 min** — may be too long for casual play; needs validation
2. **Decay accumulation rate (0.1/sec)** — may be too punishing for Heavy Doctrine; tune via playtest
3. **Eclipse trigger threshold (5000)** — should hit roughly once per match in most games; verify
4. **Population caps** — current values are heuristic; need adjustment based on actual engagement scale
5. **Resource gather rates** — military 1280/min cap may be too aggressive; verify against tech costs
6. **Doctrine commit window** — 8:00–15:00 may be too narrow or too wide
7. **Win condition thresholds** — 60%/50%/800 are anchor guesses; will need significant retuning
8. **1v1v1 vs 1v1 viability** — game is designed for 1v1v1, but 1v1 should be playable; current numbers may favor one mode unintentionally
9. **AI / single-player feasibility** — not specced; significant separate effort

---

## 19. Glossary

| Term | Definition |
|---|---|
| **Tainted** | Ground state: infested, default condition of unclaimed map |
| **Clean** | Ground state: claimed, fortified, or actively patrolled; no zombie spawns |
| **Decayed** | Ground state: military-corrupted; high spawn density, tribal-favorable |
| **Doctrine** | Faction-wide strategic commitment, locked in minutes 8–15 |
| **Force-spawn** | Tribal Shaman ability to manually trigger zombie spawn from a building |
| **Conversion** | Tribal ritual transforming enemy elite corpses into themed zombies |
| **Cremation** | Action preventing a fallen unit from returning as enhanced zombie |
| **Enhanced Return** | Fallen unit reanimating as a tougher zombie variant |
| **Network Reach** | Military win condition: control of road junction coverage |
| **Horde Mass** | Tribal win condition: total zombies sustained on map |
| **Territory** | Survivor win condition: contiguous owned map area |
| **Eclipse** | Map-wide event triggered by accumulated noise; massive zombie surge |
| **Walker** | Tribal gathering unit; ignored by zombies |
| **Looter** | Military gathering unit; loud, dangerous, fast |
| **Scout** | Survivor gathering unit; silent, limited count |

---

*End of Document v0.1*

*Next version: incorporate playtest data from first internal alpha; expand unit upgrade table to full 48 entries; specify campaign structure if greenlit.*
