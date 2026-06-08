# THE LONG WAKE — Netcode & Determinism Reference

*Distilled 2026-06-08 from a StarCraft 1 / Brood War architecture brief. This file records DECISIONS and PRINCIPLES; the full research brief is the backing source. CLAUDE.md's Determinism Rules are the enforceable version of this document — when they conflict, fix the conflict, don't pick one silently.*

## The model we are building toward

Lockstep peer simulation: every client runs the identical sim and exchanges only **player commands**, never unit state (no positions, HP, or stats ever cross the wire). Identical start + identical inputs in identical order → identical output. The network carries inputs; the price is that **any divergence between clients is fatal and unrecoverable** (the sim diverges further every tick until a checksum mismatch ends the game). This is the only model that scales to many units on tiny bandwidth, and it is what the CLAUDE.md rules exist to make possible.

This is a *target*, not current state. No netcode exists yet. The point of recording it now: every new gameplay system should be written so it doesn't have to be torn up when netcode lands. Writing to the target is nearly free now; retrofitting is brutal.

## Decisions (made, canonical)

1. **Sim math: float-with-discipline, NOT fixed-point** (decided 2026-06-08). Keep Godot-native float `Vector2`/floats for sim quantities. SC used fp8 integer math to dodge 1998-era C++ AMD-vs-Intel transcendental divergence; GDScript runs in a VM on 64-bit doubles with a far smaller cross-machine divergence surface, PC-x86 primary. Full fixed-point would be a massive retrofit fighting Godot's float-native nodes at every turn. Mitigations that make this safe (see CLAUDE.md rules #5, plus new): no transcendentals (`sin`/`cos`/`atan`/inverse-sqrt) in gameplay math; no float accumulation in long-lived sim state (use fixed-step accumulators); keep the sim layer structured so positions/combat *could* swap to fixed-point later. **Revisit only if real cross-machine desyncs appear in testing** — which is why the replay+checksum harness below exists.

2. **Counter system gets its seams now** (decided 2026-06-08). The `CombatUnit` substrate carries `damage_type`, `unit_size`, and `armor` fields plus one central damage-resolution function, even with neutral values to start. See DESIGN_MASTER §"Counter System" for the design target. Rationale: retrofitting a counter matrix into per-unit combat later is exactly the expensive surgery the seams avoid.

3. **FFA topology: host-collects-and-rebroadcasts, not full mesh** (provisional, netcode-era). A full 6-player mesh is 15 peer links and the slowest peer gates everyone every turn. A single client-host (or light relay) that collects and rebroadcasts commands bounds connection count and simplifies NAT traversal — while the simulation stays fully deterministic lockstep (the host is a *transport* convenience, never a sim authority).

## Determinism causes → our rules (why CLAUDE.md is shaped the way it is)

The four classic desync causes and the rule that kills each — this mapping is the reason the rules exist:

- Mismatched RNG call counts → **Rule #1** (single seeded SimRng, fixed call order). Branching RNG on anything client-local is the #1 desync.
- Order-dependent iteration → **Rule #4** (stable spawn-ordinal ids; never iterate `get_nodes_in_group()` where order affects outcome; instance ids are not stable across clients).
- Float/hardware paths → **Rule #3** (read coarse grids, not physics queries) + Decision #1 (no transcendentals).
- Local-factor reads (free CPU, settings, render state) → **Rule #6** (sim never reads render state).
- Slow float accumulation in sim state → **Rule #5**. The slowest, nastiest desync class.

## Build-early, netcode-era (record now, do later)

- **Replay = recorded command stream + seed + map, re-simulated.** Nearly free once the sim is deterministic (persist seed + command log; size scales with APM×duration, not world size). It is also the single best automated determinism test: record a match, replay it headless on every build, any divergence is a desync bug caught before players see it. Pairs directly with the existing SimRng + MatchStats + headless-verify infrastructure — much of the plumbing already exists.
- **Per-tick (or per-N-tick) state checksum in dev builds.** Hash sim state and compare across clients so desyncs scream immediately instead of drifting silently for minutes. Add the day netcode work starts.
- **Input-delay buffer:** commands issued on tick T execute on T+N (start ~3–4 ticks). Gives packets time to arrive; the N is the responsiveness-vs-jitter-tolerance dial (SC's "latency" setting).
- **Fixed-tick sim, batched recomputes.** SC advances logic on a fixed logical-frame timer independent of render, and batches expensive recomputes (vision ~every 100 frames, not per-frame). The codebase already does this (NoiseField 0.4s, DecayField 0.5s) — keep the pattern; it's both deterministic and a perf necessity at FFA scale.
- **Deterministic dropped-player resolution (FFA):** decide what a dropped player's units/buildings become (neutral / despawn / AI) and ensure every remaining client resolves it identically. A rotting abandoned base as a map hazard is on-theme (see DESIGN_MASTER open questions).
- **Fog of war as a per-team bitfield on the coarse grid,** computed in the sim (never read back from render), recomputed on a batched cadence. This is also where the [OPEN] "does loudness leak through fog" question gets answered.

## The one-line version

Ship inputs, not state. One seeded RNG. Fixed tick. Read the grids. Stable order. No floats you can't trust, no transcendentals, no render reads in the sim. Build the replay system as your determinism CI. Everything else is tuning.
