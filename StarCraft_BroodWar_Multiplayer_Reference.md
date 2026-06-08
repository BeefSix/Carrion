# StarCraft / Brood War Multiplayer — Architecture & Design Reference

*Deep-research brief compiled 2026-06-08 for **The Long Wake** (codename Carrion). Purpose: use StarCraft 1 / Brood War (BW) as a battle-tested reference for a competitive, asymmetric, multi-faction RTS targeting **lockstep-deterministic multiplayer (up to 6-player FFA) in Godot 4 / GDScript**.*

> **Sourcing caveat.** Blizzard never published an official SC1 netcode postmortem. Almost everything technical below comes from three credible, self-consistent source classes: (a) the canonical RTS-lockstep reference — the Age of Empires *"1500 Archers on a 28.8"* GDC paper, whose model SC demonstrably shares; (b) reverse-engineering projects (**OpenBW**, **BWAPI**, **screp**, **BNETDocs**, **IMFreedom KB**); and (c) community wikis (Liquipedia, StarCraft Fandom). Where a specific constant is documented for AoE/Supreme Commander but only *inferred* for SC1, it is flagged. Confidence levels (High/Med/Low) are carried through from the underlying sources.

---

## 0. Executive summary — the five things that matter most for The Long Wake

1. **Lockstep = ship inputs, not state.** Every client runs the identical simulation and exchanges only player *commands*; nobody ever sends unit positions or health. This is the only model that scales to "thousands of units, tiny bandwidth," and it is exactly what your `CLAUDE.md` determinism rules are setting you up for. The price is brutal: *any* divergence between clients is fatal.
2. **Determinism is a discipline, not a feature.** SC1 is **entirely grid-based and uses fixed-point math (`fp8`, 8 fractional bits)** for movement and combat — it avoids floats in gameplay precisely to stay reproducible. Your no-bare-`randf()`, fixed-tick, read-the-grids rules are the same medicine.
3. **Commands execute on a delayed turn boundary.** Input you issue now runs a few turns in the future, giving packets time to arrive. The "latency" setting is just *how many turns are in flight* — a buffer-vs-responsiveness dial.
4. **Replays and netcode are the same system.** A BW replay is just the recorded command stream + seed + map, re-simulated. If your sim is deterministic, replays are nearly free and tiny; if a replay desyncs, you've just found a nondeterminism bug. Build the replay system early — it is your best determinism test harness.
5. **Asymmetry is the depth, the counter-math is the engine.** Three non-mirrored races + a damage-type-vs-size-vs-armor counter system + splash/detection/caster layers = "no best unit, only best composition." This is the design lesson that maps directly to your three-faction zombie ecosystem.

---

## 1. Netcode & determinism

### 1.1 The lockstep model — commands, not state
SC/BW uses a **peer-to-peer synchronous lockstep** model: every machine runs the identical simulation and exchanges only player *commands* (move, attack, build, morph), never per-unit state. Start identical + apply the same inputs in the same order → outputs stay identical, so the network only carries inputs. *(Confidence: High.)*

> *"run the exact same simulation on each machine, passing each an identical set of commands… execute in exactly the same way at the same time and have identical games."* — AoE "1500 Archers" paper.

> *"only the client commands player commands are exchanged… Note there is no unit positions, health, or stats updates ever. Even when they get build or die. Only what player clicks and orders."* — ModDB, *About StarCraft networking model*.

A single **match RNG seed** is fixed at game start and drives the whole game; "the sequence they come in is not [random] and this sequence is picked at game start and is used for the duration of the game." *(High.)* This is the literal justification for your `SimRng.gd` autoload.

### 1.2 Command transport & message classes
BW commands travel via **Storm** (`storm.dll`) over a **UDP** protocol, client-to-client. Storm classifies messages:
- **Class 1 (unsynchronized):** chat, lobby — sendable any time.
- **Class 2 (game-state-synchronized):** unit orders — **sendable only once per game turn**, queued internally until the turn is transmitted. *(High — BNETDocs.)*

Each turn, every client sends a Command-Group-2 packet containing its sub-commands, **or a special NULL / keep-alive packet if it had no orders**. A new simulation turn starts only "when it has gotten all packets for that time step from all connected clients." *(High — ModDB; corroborated by the `KeepAlive` command type in the screp replay parser.)*

### 1.3 Delayed-turn execution & the "latency" dial
Commands issued on a turn are **not** executed that turn — they're scheduled a fixed number of turns ahead so packets can arrive. In AoE the offset was **2 communication turns**; SupCom used an issue-on-tick-1 / execute-on-tick-4 scheme. SC1 governs this via two values:

- **Turn Rate (TR):** game turns processed per second. Pre-Remastered it was **fixed: TR24 on LAN, TR8 on Battle.net** (which is why classic Bnet felt laggier than LAN). Remastered exposes TR up to the engine max of 24. *(High.)*
- **User Delay (UD):** the Low / High / Extra-High setting. Remastered resolves these to **UD = 2 / 3 / 4**. Higher = more turns "in flight." *(Med-High — exact integer mapping is the one mild source disagreement; older docs say 1/2/3.)*

Max tolerable round-trip is `MaxLatencyPermitted = 1000 × (UserDelay + 1) / TR` ms. At TR24 that gives **Low ≈ 125 ms, High ≈ 167 ms, Extra-High ≈ 208 ms**. *(Med-High — community-derived but self-consistent with the 2/3/4 mapping.)*

**The tradeoff (universal to lockstep):** bigger buffer = more input lag but more tolerance for jitter/packet loss before the game *stalls*; smaller buffer = snappier but the game stutters/waits if any packet is late. *(High.)*

### 1.4 Tick rate & sim/render separation
SC1 advances logic on a fixed **logical-frame** timer, independent of rendering (graphics + input poll run even when a logic frame is waiting). On **"Fastest"** (competitive default) a frame is **42 ms ≈ 23.81 logical FPS**. Full table:

| Speed | ms/frame | logical FPS |
|---|---|---|
| Slowest | 167 | 5.99 |
| Slow | 83 | 12.05 |
| Normal | 67 | 14.93 |
| Fast | 56 | 17.86 |
| Faster | 48 | 20.83 |
| **Fastest** | **42** | **23.81** |

*"The smallest unit… is called a frame. This is the atomic unit for game logic, nothing that happens in the game can take less than one frame."* *(High — OpenBW/StarCraftAI.)* **This is precisely your `CLAUDE.md` rule #2** (fixed-tick gameplay; rendering/UI may use `_process`). SC proves it works at scale.

### 1.5 Staying in sync — checksums
Clients periodically **hash their game state and compare**; a divergence is what's detected as out-of-sync. SupCom hashes **the entire game state once per second** — "If any clients disagree on the hash that's it. Game over." AoE checksummed "the world, the objects, the Pathfinding, targeting and every other system." The screp parser confirms BW has a periodic **`Sync` command** in its stream. *(High on mechanism; the exact "once per second" cadence is documented for SupCom, inferred for SC1.)*

### 1.6 Desyncs — causes, detection, handling
A desync is divergence between sims. Because divergence **compounds**, there is **no recovery** — the game detects the checksum mismatch and terminates. *(High.)*

> *"Something in their SimTicks varied and now the games are different. They have diverged and they will only get further apart from this point on. There is no recovery mechanism."* — ForrestTheWoods.

**Classic causes** (all are determinism bugs): uninitialized variables, dangling pointers reused by the allocator, **mismatched RNG call counts**, **float divergence across machines**, **processing items in different orders**, and any path that reads a *local* factor (free CPU time, hardware, settings). Tiny initial differences amplify — the AoE "deer foraging slightly off → villager paths wrong → checksum mismatch minutes later" butterfly effect. *(High.)*

> Your `CLAUDE.md` rules map 1:1 onto these causes: **rule #1** (single seeded RNG) kills mismatched-RNG-count desyncs; **rule #4** (no unordered `get_nodes_in_group()` iteration) kills order-dependence desyncs; **rule #3** (read coarse grids, not physics queries) kills hardware/float-path desyncs; **rule #6** (sim never reads render state) kills local-factor desyncs.

### 1.7 Fixed-point vs floating-point
**SC1 avoids floats in gameplay.** It uses a fixed-point type **`fp8` (8 bits fractional precision)** for movement, hit-chance, etc., and is **entirely grid-based** (Position = 1 px; WalkPosition = 8×8 px; TilePosition = 32×32 px). *(High — OpenBW/BWAPI.)*

Floats *are* deterministic per IEEE-754 but **not reproducible across machines/compilers/builds** without forcing the same instruction set, FPU precision and rounding mode — and transcendentals (`sin`/`cos`/`tan`, inverse-sqrt) **differ between AMD and Intel** because IEEE-754 doesn't pin their exact bits. AAA practitioners (Gas Powered Games, Pandemic) confirm this on the record.

> *"Battlezone 2 used a lockstep networking model requiring absolutely identical results… we discovered that AMD and Intel processors produced slightly different results for transcendental functions… so we had to wrap them in non-optimized function calls."* — Ken Miller, Pandemic.

**Lesson for Godot/GDScript:** GDScript floats are 64-bit and GDScript itself runs in a VM, which removes *some* cross-compiler variance — but you should still treat float accumulation in long-lived sim state as a latent desync source (your `CLAUDE.md` rule #5). The robust escape hatch many lockstep devs choose, and the one SC used, is **fixed-point / integer math for all gameplay quantities**. Strongly consider an integer or `fp`-style fixed-point convention for positions, velocities, and combat math in the sim layer.

---

## 2. Lobby & match infrastructure

### 2.1 Hosting model: P2P gameplay, Bnet for matchmaking only
Battle.net (BNCS) provided **chat, account/CD-key auth, the game list, and brokering the initial connection** — it did **not** relay gameplay. Once a match starts, gameplay is **peer-to-peer over Storm UDP** in a **fully-connected mesh**: the host's job is to bootstrap connections so every player ends up directly connected to every other player; the host is **not** an authority/relay during play. *(High — IMFreedom KB, BNETDocs.)*

> *"Battle.net… has always provided three basic things, chatting, matchmaking, and player statistics."* / *"The game host manages connecting to the other players to create a fully connected network."* — IMFreedom KB.

All clients bind **UDP port 6112**, which is why port-forwarding mattered for hosting. *(High.)*

> **6-player FFA implication:** a full mesh of N players is N×(N−1)/2 links — at 6 players that's **15 peer connections**, and every client must receive *every* other client's commands each turn before the turn can advance. The slowest/laggiest peer gates everyone. For FFA at 6 you should seriously weigh a **client-host or dedicated-relay** topology (one authority collects and rebroadcasts commands) over pure mesh, to bound connection count and simplify NAT traversal — while keeping the *simulation* fully deterministic and lockstep.

### 2.2 Lobby & join flow
One player creates/hosts a game (advertised in the game list); up to 7 others join (8 total). Pre-game lobby actions — pick slot/team/race, ready, fetch map + options, lobby chat — flow over **Storm "Command Group 1" between clients, not through Bnet**. *(High mechanism; Med on exact opcodes — ModDB + screp header fields confirm host & map are recorded per game.)* Players lacking the host's map **download it in-protocol** (a `DownloadPercentage` command exists; downloaded maps land in `\Maps\Downloads\`). *(Med — the existence of in-game transfer is confirmed; the chunk-level protocol wasn't read.)*

### 2.3 Drop / lag handling
Because lockstep can't advance a turn until **every** client has reported, a client that falls behind or stops sending **stalls the whole game** — this is the infamous **"lag screen."** Resolution is to wait for catch-up or **drop** the lagging player; a player leaving emits a **`LeaveGame` command carrying a reason** (drop/quit/etc.), which is recorded in replays. *(High.)* The widely-described multiplayer **"drop vote" UI** is player lore; an explicit vote *packet* wasn't confirmed at protocol level — the verified mechanism is timeout-based stall-then-drop. *(Low on a formal vote message.)*

> **FFA design note:** decide early what happens to a dropped player's units/buildings in a 6-way FFA (become neutral? despawn? AI takeover?), and make that decision **deterministic** — every remaining client must resolve it identically.

### 2.4 Replays = recorded command stream
A BW `.rep` is **header + command stream + map data + player names** — *not* video and *not* per-frame state. Playback **re-runs the deterministic engine** over the recorded commands. *(High — confirmed at file-format level by the screp parser.)*

> *"Every given command is recorded and literally replayed by the engine afterwards… only the very first buildings and workers of a player are noted in the file; every new action will be actually re-played."* — Liquipedia.

File layout (per screp): Replay-ID → **Header (0x279 bytes)**: engine version, total frame count, title, map W/H, slots, speed, host, map name, 12 player structs, colors → **Commands section**: per-frame `[frame# (u32)][block size (byte)][commands…]`, each command tagged with `PlayerID` + type (RightClick, Select, Train, Build, TargetedOrder, Tech, Upgrade, Morph, Chat, Vision, Alliance, LeaveGame, **KeepAlive**, **Sync**, …) → Map (CHK) data → player names.

**Crucially:** a replay only reproduces correctly on the **exact engine version** that recorded it; cross-version playback desyncs because logic changes alter the deterministic result of the same commands. This fragility is the *same* nondeterminism that breaks multiplayer — which is why replays double as a determinism test.

> **Build this early for The Long Wake.** A replay system is (a) nearly free once the sim is deterministic — just persist the seed + command log; (b) tiny — size scales with APM×duration, not world size; and (c) **your single best automated determinism regression test**: record a match, replay it headless on every build, and a divergence = a desync bug caught before players ever see it. This pairs perfectly with your `CLAUDE.md` headless parse-check verification step.

---

## 3. Maps & fog of war

### 3.1 Tile structure (three nested grids)
BW is entirely grid-based; isometric terrain is 2D sprites over a flat grid, collisions checked at pixel level. Three nested spatial units *(High — OpenBW/BWAPI, Liquipedia)*:

| Unit | Size | Used for |
|---|---|---|
| **Position** | 1 pixel | exact unit location, collisions |
| **WalkPosition** | 8×8 px | **walkability / pathing resolution** |
| **TilePosition** ("Cell") | 32×32 px | building placement, terrain, height |

A build tile = a 4×4 block of walk tiles = 16 "mini-tiles," each storing height/walkability flags. Per-tile properties: **Buildability, Walkability, Explored flag, Visible flag, Creep/Power**. Walkability is resolved at the 8×8 level (a partially-walkable tile is unbuildable). The engine also groups tiles into **Regions** as pathfinding nodes. Terrain has **3 height levels** (low/high/very-high), each with a "doodad" variant that acts as cover. *(High.)*

> Your `CLAUDE.md` already mandates reading coarse grids (ZombieField, NoiseField, DecayField, steering field) instead of physics queries — this is exactly BW's design (read tile/walk grids, not a physics engine), and it's *why* BW stays deterministic. The 1px / 8px / 32px nesting is a proven template for separating collision-precision from path-precision from placement-precision.

### 3.2 Fog of war — three states, two flags
Three states, implemented as **two per-tile flags**:
1. **Unexplored** ("black mask") — fully black, no terrain — neither flag set.
2. **Explored but not visible** — terrain + last-known buildings under grey fog — `explored` set, `visible` clear.
3. **Currently visible** — live vision — both set.

`explored` **persists once set**; `visible` toggles. Under grey fog, terrain stays but units/changes freeze at last-known state until you re-scout. *(High.)*

### 3.3 Vision & sight radius
Every unit has a **hidden sight-range stat** (separate from weapon range — a Siege Tank out-ranges its own sight). Each vision update, a unit reveals a roughly circular area of radius = sight range (**+1 for ground units**). Vision recompute is **batched, not per-frame**: it fires when `frameCount % 100 == 99` (~every 100 frames), resetting tile visibility then re-stamping each unit's circle; between updates the last stamp persists. *(High.)*

**High-ground rule:** units on lower ground **cannot see up** to higher tiles (can't see up cliffs); a unit on high ground reveals lower tiles. High ground grants a **miss chance, not vision** (there is no day/night system): base ranged miss is **1/256**; if the target is on cover terrain *or* higher ground than the attacker, add **119/256** → attacks miss ~47% (i.e. **136/256 ≈ 53.1% to hit**) — *not* the "30% miss" often misquoted. Height differences don't stack. A high-ground unit isn't revealed to a low-ground enemy **even when it attacks** unless it's not cloaked (attacking sets its tile visible until the next update). *(High.)*

### 3.4 Detection (cloak / burrow / detectors)
Invisibility/detection is handled **at the unit level**, not the tile level. Cloaked units (Wraith, Ghost, Dark Templar, Arbiter field) and burrowed Zerg show only as faint outlines and aren't targetable by normal attacks — but **area/splash effects still damage them**. *(High.)*

Detection range rule *(High — OpenBW code-backed)*:
- **Grounded building detector** (Missile Turret, Photon Cannon, Spore Colony): **constant 7 tiles = 224 px**.
- **Every mobile detector** (Science Vessel, Observer, Overlord): **detection range = its sight range** — so sight-range upgrades also extend detection.

A detector can't detect while incomplete, disabled (Lockdown/Stasis), blinded (Optical Flare), or if it's a hallucination. ComSat Scanner Sweep reveals an area (incl. cloaked/burrowed) temporarily. Some effects bypass true detection (Spider Mines attack cloaked units; splash damages them; Plague/Ensnare/Parasite reveal for a duration). *(High.)*

### 3.5 How fog/vision is computed in the sim
Fog is **per-player sim state on the tile grid (two flag bits per tile)**, deterministic and grid-based, **not derived from render state** — and recomputed on a **fixed batched tick** (~every 100 frames). *(High — OpenBW.)*

> Two transferable lessons: (1) store vision as a **per-team bitfield over your coarse grid**, computed in the sim, never read back from rendering (your rule #6); (2) you do **not** need per-frame vision — batching the recompute every N ticks is both deterministic and a real performance win, important when you're targeting 6-player FFA with a zombie ecosystem (potentially huge unit counts).

---

## 4. Competitive design & asymmetric balance

### 4.1 Three genuinely asymmetric races
SC was the **first RTS built on fully asymmetric races** — no shared units or abilities. Design intent, in the lead designer's words:

> *"could we make three races that didn't mirror any units or abilities with one another? So it's really the first RTS that had totally asymmetrical balance."* — Rob Pardo. *(High — documented designer quote.)*

Identities *(High)*:
- **Protoss** — expensive, individually powerful units; regenerating **Plasma Shields**; buildings need **Pylon power** (Psionic Matrix) or they shut down; warp-in. "Few but mighty."
- **Zerg** — cheap, fragile, fast; units **morph from Larvae** (auto-spawned, max 3 per hatchery) rather than built one-at-a-time, enabling parallel production; **Creep** spreads from the hive; expand early and overwhelm. The drone is *consumed* to become a building.
- **Terran** — versatile middle ground; defensive/positional (Siege Tanks, repairable mechanical units, flyable buildings, **walling** chokes with structures); combined arms. Workers must stay to finish a building.

What makes them *feel* different rather than reskinned: **distinct production paradigms** (build-from-structure vs morph-from-larva vs consume-worker), distinct economy/tech rhythms, and entirely separate unit rosters that solve air/ground/splash/detection with different tools at different timings.

### 4.2 Macro vs micro, APM
- **Micro** = controlling units individually to beat pathing/AI and keep units alive ("4 half-HP Dragoons beat 2 full + 2 dead").
- **Macro** = continuously producing units, keeping all production buildings busy, and expanding to sustain that. "The player with better macro will have the larger army."

The two **compete for the same finite attention/APM** — an opportunity-cost decision. Competitive consensus: **macro generally outweighs micro** when attention is split; when macro is equal, micro decides battles. **APM** measures execution speed and is a real skill axis, but *quality* (decisions, build optimization, scouting reads) matters more than raw quantity. The high skill ceiling comes from the macro/micro multitasking, build-order timing, and the way small errors cascade. *(High; cascade framing is analysis.)*

### 4.3 Economy
Two resources: **Minerals** (basics, low-tech, workers) and **Vespene Gas** (high-tech, late-game critical); all workers cost 50 minerals. Workers return resources in **packets of 8**; a patch saturates at **~3 workers**, after which income-per-extra-worker drops sharply — the mechanical engine that **forces expansion**. Expanding is a risk/reward bet against teching and army (a new base is a temporarily undefended investment opponents target). **Supply** (Depot/Pylon/Overlord, 200 cap) gates army size. *(High; supply specifics Med — accurate but not freshly cited.)*

### 4.4 Tech trees, build orders, timing attacks
The tech tree is a **branching** building sequence unlocking units/abilities/upgrades; each race has its own. **Tech is a commitment/risk** — investing in tech or expansion leaves you temporarily weak. A **build order** is a planned opening (measured by elapsed time or supply). A **timing attack** hits the opponent at their weakest moment — right after they've sunk resources into an expansion/tech — often syncing an upgrade to finish exactly as the army is ready. *(High.)*

### 4.5 Asymmetric-balance philosophy
The stated goal: three totally different races **"as balanced as chess."**

> *"imagine that the white side is the only side with bishops and the black side is the only side with the Queen — well how do you make those two sides completely equal so that it's the skill level of the player… that matters?"* — Rob Pardo. *(High — designer quote.)*

How it was actually achieved: **obsessive spreadsheet tuning** (per-unit damage, cooldowns, costs) + **constant top-level playtesting** — Pardo says he could only balance it *because* he was a top player. *(High — designer quotes.)*

Practical principles that transfer *(High mechanism; the framing as a framework is analysis)*:
- **Balance is per-matchup, not per-unit.** Competitive SC tracks the six non-mirror matchups (TvZ, TvP, PvZ and reverses) separately, each aiming ~50% over time.
- **Balance ≠ identical win rates — it's a viable ecosystem of playstyles.** Asymmetry is the *source* of replayability and depth; the key danger is an **exclusive dominant strategy** (only one side can run it).
- **Use the universal constraint — time.** Compare what each side can field within the same elapsed time / supply, because resource-gather / build / travel times are shared by all. Balance "macroscopically" (production over time), not just unit-vs-unit.
- **Maps are a primary balance lever.** Chokepoints favor defenders; ramp width, neutral buildings, and expansion placement tune defensibility; map pools are curated to correct matchup imbalance.

> **For The Long Wake's three-faction asymmetry:** plan to balance the **six FFA-relevant matchups** and the FFA dynamic separately, expect to live in a tuning spreadsheet, treat **exclusive dominant strategies** as the #1 threat, and treat **map design as a balance tool, not just scenery**. Your Military/Tribal/Survivor noise-profile asymmetry (loud/near-silent/silent in `CLAUDE.md`) is a real asymmetric axis — make sure each faction's weakness is as defined as its strength.

---

## 5. Unit variety & the counter system

### 5.1 Damage type × unit size (the core counter math) — *Confidence: High, all sources agree*

| Damage type | vs Small | vs Medium | vs Large (& Buildings) |
|---|---|---|---|
| **Normal** | 100% | 100% | 100% |
| **Concussive** | 100% | 50% | 25% |
| **Explosive** | 50% | 75% | 100% |

- **Buildings count as Large.** **Protoss Plasma Shields always take 100%** regardless of size/type (the universal exception).
- **Concussive is carried by only 3 units:** Firebat, Vulture, Ghost (anti-small harassers; near-useless vs Large).
- **Explosive** = most rockets/big cannons/anti-air (Siege Tank, Dragoon, Hydralisk, Missile Turret, most air-to-air).
- **Design subtlety:** most air units are Large, so most anti-air is Explosive — which is *why the Mutalisk (a Small flier) is so durable*, taking only 50% from Goliaths/Turrets/Scouts.

### 5.2 Armor — *High*
Armor is a **flat −1 per armor point, subtracted per hit, before the size×type multiplier**, and **can't reduce a hit below 0.5**. Multi-hit attacks (Zealot 2×8, Firebat, Goliath air 2×) have armor subtracted **on each sub-hit**, so heavy armor (e.g. Ultralisk Chitinous Plating) hits them hard. **Low-damage / many-hit units (Marines, Zerglings) lose a large *fraction* of their DPS to armor; high-damage single-shot units (Siege Tanks) barely notice it.** Armor does **not** reduce ability damage (Psi Storm, Irradiate, Plague ignore armor).

### 5.3 Hard vs soft counters — *High*
A **hard counter** dominates with little risk (e.g. **Dark Templar vs an enemy with no detection**, **Scourge vs capital ships**); a **soft counter** wins favorably but not totally. Canonical examples: Lurkers vs clustered bio; Vultures + Spider Mines vs small units & Reavers; Marines+Medics vs Hydralisks (small + normal beats explosive) and Mutalisks; Reavers / High Templar (Psi Storm) vs massed small units & workers; Siege Tanks vs ground (but helpless point-blank vs surrounds); Corsairs vs Overlords/Scourge; Science Vessel **EMP** vs Protoss shields/casters; Defiler **Dark Swarm** negates all ranged ground attacks.

### 5.4 Layered rock-paper-scissors — *High mechanics*
No single unit dominates; counters stack in layers:
- **Air vs ground:** many ground units can't hit air at all → air answers them, but dedicated anti-air answers the air.
- **Splash vs clumping:** the central tension — splash (Tank, Reaver, Archon, Psi Storm, Lurker, Valkyrie/Corsair, Firebat) punishes the cheap clumped swarms that are otherwise cost-efficient. Splash also hits *undetected* cloaked units in radius.
- **Detection layer:** cloak/burrow is negated only by detectors; note Sunken Colony does **not** detect (classic trap).
- **Caster layer:** spellcasters (Psi Storm, EMP, Plague, Dark Swarm, Lockdown, Stasis, Spawn Broodling, Irradiate) break unit-vs-unit math and each have their own counters (Feedback, spreading out, mechanical immunity).

### 5.5 Diversity → depth — *High*
Because every unit has a counter and each damage type is a trade-off, there is **no "best unit," only the best *composition*** for the matchup and the read. This makes **scouting** central ("read the opponent's build, choose a superior counter-composition, and attack when they're weakest") and makes **positioning** decisive (Psi Storm placement, Reaver targeting, high-ground miss chance). Iconic units exist to fill explicit roles: Marine (cheap backbone), Siege Tank (immobile artillery anchor), Vulture (fast harasser/area-denial), Mutalisk (resilient harasser), Lurker (burrowed ambush), High Templar/Reaver (anti-swarm splash), Dark Templar (binary-vs-detection), Corsair/Carrier/Arbiter (air control & utility).

> **For The Long Wake:** a small, well-understood **damage-type × unit-size × armor** matrix (SC uses just 3×3 + flat armor) generates enormous depth *if* every unit has a clear role and a clear counter. The pitfalls to avoid: a unit with no counter (becomes mandatory), a damage type that's strictly better, and armor math that accidentally hard-counters your cheap-swarm units (very relevant to a zombie-horde ecosystem — armored units could trivialize hordes, so tune horde damage type vs armored-unit size deliberately).

---

## 6. Architectural lessons & pitfalls for a Godot 4 lockstep RTS

**Do**
1. **Separate sim from render at the type level.** SC's 1px/8px/32px grids and "graphics update even when a logic frame is skipped" are the model. Your `IsoView` projection, z-index, sprite offsets are render; positions/vision/combat are sim. *(Your rule #6.)*
2. **One seeded RNG, fixed call order.** A single match-seeded `SimRng.gd`; never branch RNG on anything client-local. Mismatched RNG call counts are the #1 desync. *(Your rule #1.)*
3. **Fixed-tick sim, commands scheduled N ticks ahead.** Advance on the physics tick / explicit accumulator. Implement an input-delay buffer (start with ~3-4 ticks ≈ your "High" latency) so commands have time to propagate. *(Your rule #2.)*
4. **Read coarse grids, never physics queries, for gameplay decisions.** SC reads tile/walk grids; it does not raycast for targeting. *(Your rule #3.)* This is both a determinism rule *and* a performance necessity for FFA-scale unit counts.
5. **Stable iteration order.** Process units/buildings by a **stable spawn-ordinal id**, never by `get_nodes_in_group()` order or instance id (not stable across clients). *(Your rule #4.)*
6. **Prefer fixed-point/integer for sim quantities.** Positions, velocities, combat math. SC's `fp8` exists for exactly this reason; it sidesteps cross-machine float divergence entirely.
7. **Batch expensive recomputes on a fixed cadence.** SC recomputes vision ~every 100 frames, not per-frame. Apply the same to vision, scent/noise fields, density — deterministic *and* faster.
8. **Build the replay system early and use it as your determinism CI.** Persist seed + command log; replay headless on every build; any divergence is a desync bug. Pairs with your `CLAUDE.md` headless parse-check.
9. **Add a per-tick state checksum from day one.** Hash the sim state each tick (or every N ticks) and compare across clients in dev builds; you want desyncs to scream immediately, not drift silently for minutes.

**Watch out for**
- **Float accumulation in long-lived sim state** (your rule #5) — the slowest, nastiest desync class.
- **Full-mesh P2P at 6 players** = 15 links and the slowest peer gates everyone; consider a host-collects-and-rebroadcasts topology for FFA while keeping the sim lockstep.
- **Non-deterministic resolution of dropped-player units** in FFA — every client must resolve a drop identically.
- **Order-of-operations in combat math** — SC's armor-before-multiplier, per-hit armor, 0.5-minimum, shields-take-full are *specified* and consistent; pin your own order down explicitly or multi-hit/armor interactions will desync or feel random.
- **Engine-version-coupled replays** — your replay format will break across sim-logic changes; version-tag replays and expect to downpatch, exactly like BW.
- **An uncounterable or strictly-dominant unit/damage type** — the balance killer in asymmetric design.

---

## Sources

**Netcode / determinism**
- AoE "1500 Archers on a 28.8" (canonical RTS lockstep reference): https://zoo.cs.yale.edu/classes/cs538/readings/papers/terrano_1500arch.pdf
- ForrestTheWoods, *Synchronous RTS Engines and a Tale of Desyncs*: https://www.forrestthewoods.com/blog/synchronous_rts_engines_and_a_tale_of_desyncs/
- Gaffer On Games, *Floating Point Determinism*: https://gafferongames.com/post/floating_point_determinism/
- SnapNet, *Netcode Architectures Part 1: Lockstep*: https://www.snapnet.dev/blog/netcode-architectures-part-1-lockstep/
- StarCraftAI wiki, *Frame Rate*: https://starcraftai.com/wiki/Frame_Rate
- Making Computer Do Things (BWAPI/OpenBW), *Of time and space*: https://makingcomputerdothings.com/brood-war-api-the-comprehensive-guide-of-time-and-space/
- Liquipedia: Battle.net/Latency, Game Speed, Storm Packets — https://liquipedia.net/starcraft/Game_Speed

**Lobby / infrastructure / replays**
- IMFreedom KB — Battle.net / Storm P2P: https://kb.imfreedom.org/protocols/battle.net/
- BNETDocs — Storm UDP Protocol: https://bnetdocs.org/document/34/storm-udp-protocol
- ModDB — *About StarCraft networking model* (treeform): https://www.moddb.com/features/about-starcraft-networking-model
- icza/screp — BW replay parser (definitive .rep structure): https://github.com/icza/screp
- Liquipedia — Replays: https://liquipedia.net/starcraft/Portal:Beginners/Replays
- sc2reader — *What's in a replay*: https://sc2reader.readthedocs.io/en/latest/articles/whatsinareplay.html

**Maps / fog of war**
- BWAPI Guide — *Distances, High Ground, Unit Behavior*: https://makingcomputerdothings.com/brood-war-api-the-comprehensive-guide-distances-high-ground-and-unit-behavior/
- Liquipedia — Distance: https://liquipedia.net/starcraft/Distance
- Liquipedia — Detection: https://liquipedia.net/starcraft/Detection
- StarCraft Wiki — Fog of war: https://starcraft.fandom.com/wiki/Fog_of_war
- Code of Honor — *StarCraft path-finding hack*: https://www.codeofhonor.com/blog/the-starcraft-path-finding-hack

**Design / balance**
- Rob Pardo lecture (designer quotes): https://www.danielscrivner.com/rob-pardo-lecture-on-blizzards-game-design-philosophy/
- Simon Halliday, *StarCraft II: A Study in Asymmetrical Design*: https://simonhalliday.com/2019/09/04/starcraft-ii-a-study-in-asymmetrical-design/
- Liquipedia — Micro and Macro: https://liquipedia.net/starcraft/Micro_and_Macro
- Liquipedia — Resources / Mining / Technology tree / Build order
- Wayward Strategy — *Timing Attacks*: https://waywardstrategy.com/2015/12/09/timing-attacks/

**Units / counters**
- Liquipedia — Damage Type: https://liquipedia.net/starcraft/Damage_Type
- Liquipedia — Damage / Armor / Splash Damage
- Blizzard classic — Damage system: http://classic.battle.net/scc/GS/damage.shtml
- StarCraft Fandom — Damage types / Rocky Paper Scissors
- StrategyWiki — StarCraft/Counters: https://strategywiki.org/wiki/StarCraft/Counters

*Confidence note: SC1-specific engine internals (fp8, tile grids, vision cadence, detection ranges, damage tables, frame timings) are OpenBW/BWAPI/Liquipedia-corroborated and rated High. Exact lockstep constants borrowed from AoE/SupCom (turn-offset of 2, hash-once-per-second) are High for the architecture class but inferred for SC1. The Low/High/Extra-High → UserDelay mapping is the one mild source disagreement (1/2/3 vs Remastered 2/3/4).*
