# THE LONG WAKE — Master Design Document

**Title:** THE LONG WAKE (decided 2026-06-07; supersedes the working title *Carrion*, dropped due to collision with the 2020 Devolver game. "Carrion" remains the internal codename — repo name, class names, and code identifiers do not need renaming. Player-facing strings, store assets, and docs use The Long Wake.)
**Status:** Canonical. Supersedes `DESIGN_DOC.md` and `PROTOTYPE_PLAN.md` (retained as historical artifacts).
**Last consolidated:** 2026-06-07, from design sessions between Matt (BeefSix Studios) and Claude.
**Tagging:** Untagged statements are CANON (ruled by Matt). **[PROPOSED]** = suggested and well-received but not explicitly ruled. **[OPEN]** = tracked, undecided. See §12 for the full open-questions register.

---

## 1. Vision

Carrion is an asymmetric three-faction competitive RTS set in a long-collapsed zombie apocalypse, built on the StarCraft 1 chassis: vision-based fog of war, skirmish as the heart of the game, matches ending in last-man-standing. End goal: up to 6-player free-for-all. A 9-map campaign (3 per faction: basics → advanced → overwhelm) serves the same purpose as Battlefield 1's campaign — teach the sandbox, set the tone, then release the player into multiplayer.

**The zombies are not the enemy. They are the terrain.** A third actor that is never defeated — only read, redirected, fed, avoided, or joined. Every comparable game treats the undead as waves to repel; Carrion treats them as an ecosystem all players are embedded in.

**Tone:** 28 Days Later, The Road, Project Zomboid. Grim mechanics, restrained melancholy, long collapse. There are no good guys — picking a faction is picking which thing people became. The campaign's descent structure shows each faction degrading; multiplayer is the degraded state in perpetual conflict.

**Faction equivalency (mechanical foundation):** Tribal = Zerg, Military = Terran, Survivor = Protoss. Visually these are the bleak extremes: Military is aggressive scary men who *acquired* military gear post-collapse (Major West, Caesar's Legion, War Boys) — not an institution, a warband wearing one's corpse. Tribal is the tribe from Peter Jackson's King Kong (Skull Island, Blood Meridian). Survivor is the more aggressive groups from The Road — somewhere between a Fallout raider camp and a devolved Alexandria.

---

## 2. The Attention Economy (core thesis)

Every system expresses one idea: **the world keeps score of your presence.** Nothing you do is free; the bill arrives as zombies.

Two sensory channels with different physics:

- **Noise (sound)** — an *event*: instantaneous, long-range, decays fast. Attacks, looting, engines, broadcasts. Zombies hear and converge. Different units emit different amounts; faction strategy is partially noise management.
- **Blood (scent)** — a *state*: short-range, persistent, **trails**. Damage applies a *bleeding* status (distinct from low HP). Bleeding units deposit a scent trail that zombies follow; a wounded army retreating home drags the horde toward its own base. Spilled blood lingers — battlefields stay attractive after the fight, so corpse recovery happens inside a converging zombie cloud.

Plus two slower ledgers:

- **Decay** — DEMOTED to visual-only (decided 2026-06-08). Was: Military structures rot the ground, decayed zones spawn faster. Its gameplay jobs dissolved — the anti-(Military+Survivor)-alliance exploit it patched is now handled by Survivors clearing infested buildings into their own safe zone, and the "occupation has a price" pressure is carried by the zombie ecosystem itself. Kept as **environmental land-state imagery / intel**: Military-squatted ground looks worn/decayed, Survivor-cleared ground looks healed — in fog of war, the state of the land tells you who has been where. Implementation: sever the Lootable spawn-rate hook; keep the DecayField rendering. NOT a cost ledger anymore.
- **Corpses** — every body is a pending zombie (§4).

**Medical infrastructure:** stopping bleeding is a fast, cheap emergency verb; healing HP is slow and expensive. Medical buildings provide ambient healing in radius — a base with a medic tent doesn't smell like blood ("clean zones"). Units have a slow self-bandage floor (stops movement) so a medic-less army is desperate, not unplayable. **[PROPOSED]** Design guardrail: the fight → noise+blood → zombies → more fighting spiral needs exit ramps (medics, disengagement, Shepherds) so not every skirmish snowballs.

Sometimes it is better to let a wounded man die alone than to bring him — and the horde that follows his blood — home. That decision is the fantasy.

---

## 3. Zombie Ecosystem

### 3.0 Marrow — Tribal creep (designed 2026-06-08; name front-runner "Marrow", may change)

The only faction whose presence *transforms the ground into a gameplay surface*. Tribal's SC-Zerg-creep analogue: a spreading territory ("Marrow") emanating from Tribal structures and/or dense zombie clusters. Tribal units gain bonuses on it (TBD — likely the ambush/regen/movement edge); it visibly marks claimed ground with its own bone/viscera visuals (distinct from the decay land-state). Marrow is the *only* faction-ground mechanic with real gameplay teeth — Military wears the land down (visual-only, §2), Survivor heals/repurposes via buildings (not ground), Tribal *claims* it. Ties the previously-vague density/clustering zones into ownable territory. Numbers and exact bonuses [OPEN] → Tribal phase + balance lab. (Naming candidates considered: Marrow [front-runner], Stain, the Mire, Blight, the Reek.)

### 3.1 Clustering dynamics
Zombies roam. Zombies make noise, which attracts zombies — so they cluster, and the map develops dense zones with their own geography: living walls, no-go areas, weapons. This positive feedback loop is the keystone system and requires damping (below) or the map converges to one mega-blob.

### 3.2 The steering field [PROPOSED architecture]
One unified system: a coarse-grid attention/steering field where every influence is an emitter with a signed weight and radius — noise residue, scent trails, density, anchors (Brutes, the Marked, Callers), repulsors (Shepherds), and per-zombie home bias. All zombie movement samples this field. One system, many units; cheap, tunable, deterministic-friendly. Do not build bespoke per-unit behaviors.

### 3.3 Zombie types
**Natural:**
- **Shambler** — baseline. Slow, weak alone, dangerous in numbers.
- **Runner** — faster than humans, individually deadly, less common.
- **Brute** — slow, extremely tough, devastating up close. **Immune to noise-attraction; loud; wanders far — zombies follow it.** A walking horde-nucleus that drags its cluster across the map. Players predict horde movement by tracking Brutes; killing one orphans its cluster. Dead Brutes are a Tribal resource (§7).
- **Shepherd** — repels zombies; cuts groups apart and pushes them around. Possibly zombie dogs / all-fours. The damping mechanism for the clustering loop: kill Shepherds and blobs merge; protect them and the map stays partitioned. (Silhouette must read distinctly from Crawler.)

**Tribal-created (via Shaman, §7):**
- **Crawler** — fast, stealthy, moves on all fours through cover. The zergling; slips through Survivor perimeters and garrison windows.
- **Bloater/Boomer** — exploding plague-delivery unit.
- **The Marked** — elite anchor; ritual modifications; zombies cluster around it.
- **The Congealed** — Tribal endgame, fused from N zombies out of a cluster (§7).

### 3.4 Homeward memory
Faction-origin zombies walk back toward their faction's spawn out of latent memory. A failed attack literally comes home — and the defender can follow the returning horde and counterattack behind a zombie screen. Implemented as a weak personal *home attractor* on the steering field, **distractible by noise en route** — interceptable, herdable, lurable; a bias, not a script. This also prevents the degenerate case of dead elite attackers becoming permanent bosses in the defender's base.

### 3.5 Population governor [OPEN]
Spawn equilibrium, escalation curve over match time, and the FFA anti-turtle clock are undefined. Current code: 300 cap with known leaks (see AUDIT.md).

---

## 4. The Corpse Economy

- **All corpses can rise.** What happens to a body depends on *who killed it*.
- Clean kills come from headshots/training: Looters always kill clean; most other Military units have an **80% chance of producing a corpse** that rises. (Code currently 30% — design target is 80%.) Veterancy raises clean-kill rates (rookies miss heads — inexperience literally feeds the apocalypse).
- Corpses inherit the dead unit's strength, scaled by veterancy. **Stronger units become stronger zombies.** Your veteran squad is your best asset and the worst thing you can lose; enemies have a macabre incentive to kill elites somewhere inconvenient.
- **Shoot-to-loot:** Military Looters can loot the dead of any faction by shooting the corpse — one action that pays salvage, neutralizes the rise, and emits noise. Military cleanup cannot be performed quietly.
- **Cremation:** any combat unit, slow channel, free, quiet. The contrast with looting (fast, paid, loud) is a real decision — keep both.
- **Caustic denial (Survivor):** Chemist acid dissolves corpses silently — beats the rise *and* denies Looter salvage.
- **Battlefield aftermath:** corpse races (Looters vs. Walkers vs. the rise timer) happen on ground that blood has made attractive — everyone wants the bodies, the site is turning hostile, all on the same clock.

---

## 5. Veterancy & Squads

Four ranks. This is behavioral, not just stat multipliers — squad quality must be legible at a glance:

1. **Rookie** — poor formation, fewer headshots (more corpses produced), slower reload, fear responses (backing up while firing), split targets.
2. **Seasoned** — disciplines nearby rookies; the line straightens a little.
3. **Veteran** — squad focus-fires one target, professional formations; leads more soldiers than Seasoned.
4. **Prized** *(rank 4, difficult to achieve)* — advanced capabilities. [OPEN: specifics.]

Leadership is an aura/command-tree effect (code skeleton exists: squads, auras, succession). The rookie death spiral (fear → broken formation → more corpses) is arrested by leadership presence — visibly.

### 5.1 Behavioral autonomy + personality (designed 2026-06-08; from first feel-test)

The first feel-test revealed units feel like "all me" — puppets with no autonomous life. The fix is the same behavioral system across three complementary axes, all active on every unit: **reaction** (flinch, return fire, take cover without orders), **morale** (hesitate, hold, break, rally), **formation** (spacing, hold the line, advance steadily). These are not separate features — every unit has all three.

**Personality (rolled at spawn via SimRng, fixed for the unit's life):** a disposition archetype that tunes *which axis dominates* — not an on/off feature switch. Coherent characters, readable at a glance, turning variation into information the player accounts for:
- **Steady** — tight formation, calm under fire, breaks late; slightly slower to react.
- **Skittish** — reacts/flinches early, breaks formation and panics sooner.
- **Hothead** — aggressive, instant return fire, overcommits, hard to hold in position.
- **Green** — average baseline.

**Personality × veterancy is the richness.** Personality is the spawn baseline; veterancy is earned and **dampens the extremes, converging every survivor toward a grizzled-veteran baseline** — experience smooths disposition. A Skittish rookie is a liability (first to break, feeds the apocalypse with panicked misses → corpses); a Skittish veteran has learned to manage it; a Steady rookie punches above its rank. This is what makes the player care about a *specific* unit. Maxes the "leading individuals, not driving avatars" feeling, and feeds the corpse economy (panic → missed headshots → more corpses).

**v1 scope:** 3–4 archetypes tuning thresholds on the shared behavior system; bounded, *readable* effects (texture + information, never "my unit randomly disobeyed and it felt unfair"); SimRng-rolled. Veterancy-dampening interaction is the v2 layer. **Dependency order (critical):** these behaviors are parasitic on the threat being real — units panic/flinch/break *in response to danger*. The zombie steering field (threatening horde, §3.2) must land FIRST, or the behaviors are reacting to a harmless shuffling pile. Threat first, then the behaviors that answer it.

Readability feeds the information game: get eyes on a fight and tracer convergence tells you whether that garrison is green or salted.

**Snowball caution:** veterancy is winner-gets-stronger, and rank 4 amplifies it. Counterweight is built in (a dead Prized unit is four ranks of power walking home as a corpse) but tune deliberately; build match telemetry from day one. **[PROPOSED]**

---

## 6. Balance Model & Doctrines

- Intended pressure triangle: **Tribal > Military > Survivor > Tribal.** Each edge is mechanical: Military's noise and corpses feed Tribal; Military's suppression cracks the cover Survivor needs; Survivor's walls and silent weapons starve Tribal's ecosystem leverage.
- **The triangle should live in doctrines, not base factions** **[PROPOSED]**: base matchups roughly even (Brood War's lesson — designed faction-level RPS poisons 1v1), with doctrine commitments swinging matchup effectiveness. In 6p FFA, soft RPS is healthy (diplomacy).
- **Doctrines** are upgrade commitments for some units of each faction, specializing them against specific factions. Generally two paths per unit, one anti-Military lean, one anti-Tribal/anti-Survivor lean.
- **[OPEN]** Scoutability ruling. Recommendation: doctrine shows on the unit (gear silhouette — the art pipeline carries this), so reading enemy commitments requires getting eyes on their army, which under fog+noise is itself a risk.
- Doctrine grammars by faction: **Military trades on noise** (one path louder, one quieter), **Tribal trades on the cluster**, **Survivor trades on what gets repurposed**.

### 6.1 Counter System (from the SC/BW reference, adopted 2026-06-08)

The engine of "no best unit, only best composition" is a small counter matrix, not unit count. SC achieved enormous depth with just **damage-type × unit-size (3×3) + flat armor**. The Long Wake adopts the same shape; values are [OPEN] and will be tuned in the balance lab, but the *seams* go into the `CombatUnit` substrate now (`damage_type`, `unit_size`, `armor`, one central damage-resolution function) so the matrix can be tuned later without per-unit surgery.

Design targets and pitfalls carried over:
- Resolve damage in a **pinned order**: armor subtracted first (flat −N, per sub-hit for multi-hit attacks, floored at a small minimum), then the size×type multiplier. Order must be explicit or multi-hit/armor interactions desync or feel random.
- Three pitfalls are the balance killers: a unit with **no counter** (becomes mandatory), a damage type that is **strictly better**, and armor math that **accidentally hard-counters cheap swarms**.
- **Zombie-horde-specific warning:** armored units could trivialize hordes. Tune horde damage-type vs armored unit-size *deliberately* — this is the central tension of the whole ecosystem (the cheap swarm must stay threatening to armor, or the noise/corpse economy loses its teeth).
- Balance is **per-matchup, not per-unit** (~50% per matchup over time), measured against the universal constraint of **time/supply** (what each faction fields in the same elapsed time), with **maps as a primary balance lever**. The balance lab is the spreadsheet SC tuned by hand.

See NETCODE.md for the determinism decisions (float-with-discipline, no transcendentals) that shape how all combat math is written.

---

## 7. The Factions

### 7.1 Military
**Identity:** post-institutional warband. Predatory toward civilians. Loud. Commits. Suppression mechanic; vulnerable to flanking. Postures: Engage / Hold / Withdraw.
**Relationship to ecosystem:** fights through it and *metabolizes* it — their noise attracts zombies, their Looters farm the arrivals. They convert nothing: deplete and sweep. Pure extraction, living on a clock — the faction that should want to attack. Their decay zones are creep that works against them.

**Suppression (combat identity, designed 2026-06-08):** a short-lived *field* fed by fire and read by position — same architecture as NoiseField (a decaying source-list, but fast-decay and small-radius). Every ranged shot that lands deposits suppression at the impact point. **Source is universal, but threshold requires volume** — one shooter's deposits decay before crossing the line, so a lone unit suppresses nothing; concentrated/sustained fire on one area builds a zone. Military's loud, massed, high-rate weapons dominate it by playstyle; Tribal's silent single-shot Hunters and Survivor's quiet crossbows barely register. Military *owns* suppression by volume, not by rule. Any unit in a suppressed zone — **human or zombie** — is slowed and fires less accurately (speed + accuracy). The zone dissipates in ~1–2s after fire stops. **Thesis interaction is free:** the suppressing fire already emits noise via NoiseBus, so pinning a horde simultaneously summons the next wave — Military buys control with noise, made mechanical. v1 is a flat debuff; **v2 hook**: veterancy resistance (rookies break under suppression, veterans hold — ties into behavioral veterancy §5). All numbers placeholder → balance lab.

**Units:**
- **Looter** (economy) — on spawn, patrols Military zones: clears zombies, builds salvage. Trained in headshots (always clean kills). Shoot-to-loot on corpses of any faction (§4).
- **Rifleman** (basic attack) — doctrines: **Ghost** (silencer; less range/damage; quiet — anti-Tribal) / **Shotgunner** (much louder; less range; high damage; CQB breaching — anti-Survivor).
- **Heavy Gunner** — loud, high-damage group clear, medium range. Doctrines **[PROPOSED]**: **Entrencher** (tripod deploy: stationary, wider arc, stronger suppression — a temporary turret, anti-Survivor siege) / **Incinerator** (incendiary belts: lower DPS, **kills leave no corpses** — the only Military firepower that clears a horde without manufacturing the next one; anti-Tribal).
- **Engineer** — required for Command Post upgrades and doctrine upgrades. Grenades; blowtorch for close combat — and the blowtorch is the faction's fastest cremation tool **[PROPOSED]**.
- **Medic** — doctrines **[PROPOSED]**: **Stim** (combat drugs that suppress rookie fear behaviors — chemically-induced discipline; costs HP or a crash) / **Graves** (corpse processing: your dead stay dead; field salvage extraction; plague countermeasures).
- **Humvee** (endgame) — the engine is a noise emitter *that cannot be turned off*: maximum power, maximum consequence, made physical. Crushes through shambler packs. A wreck does not rise — the one Military endgame asset that doesn't feed the ecosystem (unlike a rank-4 veteran). Doctrines **[PROPOSED]**: **Weapons platform** (mounted gun) / **Transport** (carries a squad).

**Buildings:** Command Post; Barracks (Rifleman, Heavy Gunner); Engineer building/workshop; Medic tent (ambient-healing clean zone); Turrets — automated fire is a noise liability bolted to your base; every defensive burst summons the next wave; give them fire-discipline postures (free-fire / hold / targets-of-opportunity) so the player owns the noise decision. **[PROPOSED]** **Listening Post** — institutional radio gear that pings loud events through fog within a radius; the loud faction is also the one listening (their comsat).
**Elimination condition:** HQ/Command Post.
**Medic threshold (what their medical class guards):** the corpse ledger and the fear ledger.

### 7.2 Tribal
**Identity:** transformed post-civilizational faction, symbiotic with the dead. Hit-and-run from within zombie clusters; ambush bonus; vulnerable to losing the Caller. Postures: Stalk / Strike / Withdraw.
**Zombie immunity — blood breaks the mask:** healthy Tribal units walk among the dead untouched, always. A *wounded* unit (bleeding/burning) reads as prey — the ritual hides you; bleeding gives you away. Immunity is a practice maintained, not a property owned. This mechanically enforces Strike/Withdraw, makes the Hunter's living armor double-edged when fights sour, gives Military/Survivor counterplay (sustained fire and incendiary *feed Tribal to their own horde*), and makes the Plague Spreader's healing literally invisibility maintenance. **[PROPOSED, optional layer]** Wild Brutes are too rage-blind to respect the mask, pricing Walker harvesting of dead Brutes.
*(Wounded-exposed state must be readable at a glance — e.g., nearby zombie heads turning toward a bleeding unit.)*

**Economy:** Walkers gather **ritual mats** from infested buildings and dead Brutes. Tribal's resource nodes are everyone else's threats — they want infestation to spread. They convert depleted/enemy resource buildings into infested spawners (the inverse of Survivor clearing). [OPEN: ritual mats — flavored salvage or true second resource?]

**Units:**
- **Walker** (economy) — zombie-immune scavenger. Doctrines **[PROPOSED]**: **Bone-carrier** (carry capacity, fast Brute harvest) / **Seeder** (slowly infests depleted buildings — economy→hazard conversion at the worker level).
- **Hunter** (basic ranged) — bow; emits a constant clicking that keeps zombies clustered *around him*; fires from inside the group. Deliberate noise as armor. Counterplay: scatter or kill the cluster, or steal it (Saboteur lures). Doctrines **[PROPOSED]**: **Still-path** (drops the clicking: no cluster, longer range, true silent stalker) / **Deep-click** (louder, bigger cluster, plague-tipped arrows — a walking horde nucleus brought to Military's door).
- **Shaman** — overlord-equivalent and **the faction's supply system [PROPOSED]**: zombie units require control capacity provided by Shamans/Callers. Channels at infested buildings to change what they spawn. Doctrines **[PROPOSED]**: **Flesh-shaper** (Crawlers) / **Bile-shaper** (Bloaters). Endgame: **the Congealed**, fused from N zombies out of a cluster — paid in ecosystem mass, not salvage.
- **Caller** (signature) — Aztec death whistle; buffs and organizes zombies; the anchor and the stated faction weakness. Doctrines **[PROPOSED]**: **War-caller** (drive the horde: aggression, focus) / **Herd-caller** (precision: split, park, screen; later path to taming Shepherds — absorbs the Beastmaster concept).
- **Plague Spreader** (medic) — plague heals Tribal and zombies, harms enemies. Doctrines **[PROPOSED]**: **Mender** (sustain, mask maintenance) / **Blighter** (offensive plague: infected enemies *always* corpse on death and rise tribal-aligned — killing your own enemies becomes dangerous).

**Control rule:** when a Caller or Shaman dies, controlled zombies **instantly revert to wild** — and freshly wild zombies re-run normal aggro, usually onto the loud battle that just killed their handler.
**Buildings:** minimal built footprint — camp + ritual site; production is infested map features, supply is units, economy is the hazard.
**Elimination condition:** [OPEN — they barely build; likely tied to camp/priests.]
**Medic threshold:** the mask.

### 7.3 Survivor
**Identity:** extreme survivors — more civilized than a raider camp, slightly devolved Alexandria. Improvised gas masks, faces hidden. Cover-to-cover repositioning, cover bonus, vulnerable in the open. Postures: Push / Defend / Fall back.
**Medium — the map itself:** Military wears civilization's corpse, Tribal abandoned it, Survivors *re-inhabit* it. Their verb is **repurpose**: loot buildings → supplies; clear infested buildings → resource points; garrison buildings → turrets; cars → alarm traps; radio stations → economy. Their creep-equivalent is renovation: cleared, fortified, inhabited territory.

**Economy:** **Farms are the pylons. Radio stations attach to farms** and control the economy — broadcasts call civilians in; civilians become recruitable population (units cost civilians + supplies, which is why this faction is few-and-precious and why losing veterans hurts most). **[PROPOSED]** Broadcast volume is a dial: recruiting harder means broadcasting louder means calling the dead along with the living — the Heavy Gunner decision on the economic axis. [OPEN: can enemies prey on civilians en route? Military is canonically predatory toward civilians.] The Negotiator concept folds into this system as a recruitment accelerator.

**Units:**
- **Runner** (economy) — Glenn from The Walking Dead: bags and a big knife. Fast, stealthy; sprint + fatigue mechanics; loots buildings for supplies; stealth-stab one-shots basic enemies, slow recovery. (Code: the Scout's energy system is this unit's skeleton.) Doctrines **[PROPOSED]**: **Infiltrator** (deeper stealth; sabotage structures, steal from stockpiles) / **Courier** (longer sprint, bigger bags, **can carry a wounded unit** — hauling a bleeding casualty out before the scent trail forms).
- **Bolter** (basic ranged) — improvised crossbow, silent. Doctrines **[PROPOSED]**: **Longbolt** (sniper: clean headshot kills; the quiet bolt that takes a Caller out of his own horde — decapitation + corpse-economy answer) / **Pinbolt** (heavy bolt: armor penetration, stagger/pin — stops the Military commit).
- **Brawler** (melee) — doctrines: **Bulwark** (anti-Military): riot gear, tower shield — *he is cover*; mobile cover others fight from behind; suppression resistance. / **Hatchet [PROPOSED]** (anti-Tribal): cleaving sweeps vs. Crawler packs and shambler clumps.
- **Saboteur** (specialist) — sound grenades and car-alarm traps: remote control for the horde; the faction's zombie verb (Military fights the ecosystem, Tribal joins it, Survivor *redirects its attention*). Doctrines **[PROPOSED]**: **Demolitionist** (absorbs the Bomber: breaching charges, rigged cars — the one Survivor unit that chooses noise) / **Whisperer** (sound dampeners that deaden a zone; lure mastery that hijacks clusters — stealing a Hunter's living armor mid-fight).
- **Chemist** (medic) — they don't have medicine, they have chemistry. Doctrines **[PROPOSED]**: **Apothecary** (plague antidotes, squad immunization, fast bleeding control) / **Caustic** (corpse-dissolving acid — silent corpse denial; thrown caustics degrade armor).
- **Builder** — places palisades and **builds garrisons**. Doctrines **[PROPOSED]**: **Fortifier** (reinforced palisades, spiked kill-zones, hardened garrisons) / **Trapper** (barbed wire and snares that catch Crawlers; alarm tripwires that reveal stealth).
- **The Bus** (endgame) — a building that moves. Armored, slow, tough, garrison inside. Doctrines: **Fortress** (deploys into a heavy garrison with firing ports — instant forward base) / **Caravan** (carries civilians and supplies — a **mobile settlement**; Survivor is the only faction that can pick up its elimination condition and move it; desperate, slow, unforgettable).

**Garrison mechanic:** Survivors inhabit buildings and turn them into turrets — visible figures on the roof firing bolts down. Garrisoned bolt-fire is silent: they can defend without escalating. Counters are faction showcases: Military breaches (Shotgunner) or burns (Incinerator); Tribal sends Crawlers through the windows.
**Elimination condition:** the settlement — farms and radios, not units. The Caravan can relocate it.
**Medic threshold:** irreplaceable veterancy investment, and plague.

---

## 8. Multiplayer Architecture Mandate

Competitive multiplayer (up to 6p) is the end goal, which is an architecture decision, not a feature. RTS netcode is lockstep-deterministic: identical simulation on every client, only inputs transmitted. **Build the habits now** — retrofitting determinism into 10k+ lines later is brutal; writing new systems deterministically is nearly free:

- Fixed-tick simulation; no game logic keyed to frame rate or render state.
- One seeded RNG stream owned by the sim — no bare `randf()`/`randi()` in gameplay code.
- Game logic reads the coarse grids (steering field, density, scent), not physics-engine queries.
- The steering-field architecture (§3.2) exists partly for this reason.
- A conventions document for the repo should be written so every future Claude Code prompt inherits these rules. **[PROPOSED, accepted in principle]**
- Match telemetry from day one (kills by unit type, salvage curves, win condition, match length) — asymmetric balance gets tuned with data, not vibes. **[PROPOSED]**

---

## 9. Information Warfare

- Fog of war is vision-based (SC1): you see only what your units see.
- Squad quality is readable from behavior (formation, tracer convergence) — scouting reads *quality*, not just quantity.
- Doctrines as scoutable commitments (pending §6 ruling).
- Zombie flows are public information: anyone can read horde drift, Brute trajectories, and returning homeward dead — the ecosystem leaks everyone's secrets.
- **[OPEN — the big lever]** Does loudness leak through fog? Options: nothing leaks (pure SC1); directional audio only (you *hear* a distant Heavy Gunner, no map info); big events ping the map above a magnitude threshold. This decides whether firing the Heavy Gunner reveals you to the zombies or to everyone. The Military Listening Post depends on this ruling.

---

## 10. Campaign

Nine maps, three per faction: **basics → advanced → overwhelm** (Battlefield 1 model — short, scripted, tonal). The descent loop is the philosophical spine: each faction degrades across its three maps. No triumphant endings. Campaign teaches the systems the competitive game runs on.

---

## 11. Production Notes

- Solo developer (Matt), AI-orchestrated workflow: Claude as design/articulation layer, Claude Code as execution layer, Gemini for character art (faction docs as style anchors), PixelLab via MCP for environment art.
- Engine: Godot 4.x, GDScript. Repo: https://github.com/BeefSix/Carrion.git
- Art must carry mechanics: doctrine silhouettes, medic legibility at combat distance, wounded-exposed states, rank insignia/behavior. The behavioral-veterancy and threshold-medic designs only work if readable.
- Audio is mechanical in this game, not cosmetic — players need to hear what zombies hear. [OPEN: audio strategy.]
- Code-level status and known bugs: see `AUDIT.md` (2026-06-07). Notable design-relevant gaps: corpse chance at 30% vs. design's 80%; zombie immunity currently Walkers-only vs. faction-wide conditional design; shoot-to-loot, blood/scent channel, behavioral veterancy, doctrines, garrisons, and all faction economies beyond salvage are unbuilt.

---

## 12. Open Questions Register

1. **Fog/noise leak** — does loudness cross fog of war, and how? (§9 — biggest competitive lever.)
2. **Ritual mats** — true second resource for Tribal, or faction-flavored salvage? Changes their whole macro.
3. **Human supply caps** — Tribal has Shaman-supply for zombies; what caps Military/Survivor army size? (Survivor: civilians, plausibly.)
4. **Civilian predation** — can Military/Tribal prey on civilians en route to Survivor radios?
5. **Elimination aftermath** — what does a dead player leave on the map? (A rotting base as permanent hazard is on-theme.)
6. **Tribal elimination condition** — what do you destroy to eliminate the faction that barely builds?
7. **Zombie population curve** — equilibrium, escalation over match time, the FFA anti-turtle clock; can factions meaningfully deplete the hazard (Looter farming)?
8. **Plague mechanics** — numbers, delivery, counterplay beyond the Chemist/Medic.
9. **Doctrine scoutability** — visible on silhouette (recommended) or hidden?
10. **Rank 4 (Prized) capabilities** — per faction.
11. **Match anatomy** — starting state, target match length, minutes 1–5 per faction.
12. **Day/night cycle** — in or out?
13. **Audio strategy.**
