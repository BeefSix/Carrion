# AI Lab Report — A6 measurement batch (2026-06-10)

**STATUS: PROVISIONAL.** Per the stapled A6 caveat (AI_OVERHAUL_PLAN.md): these
numbers were measured against a world where zombies are still weather. The
threat pass (Phase 3) changes the map's hazard topology under the AI's feet —
an **A6b re-tune is budgeted** there, and win-rate shifts at that point are the
world changing, not a regression. Tune lightly now; deeply later.

**Method:** 15 headless matches, ~9-10 sim-minutes each, zero script errors.
Seeds 411-415 = MM (Military mirror), 421-425 = MT (player-slot Military vs
Tribal), 431-435 = TM (player-slot Tribal vs Military). Winner = the side whose
telemetry continues after the other goes silent (HQ death).

## Outcomes

| Matchup | Result |
|---|---|
| MM mirror (5) | **5 draws/timeouts** — neither Military closes |
| MT (5) | **Tribal 4 wins**, 1 draw — Military dead at 1.7-2.0m |
| TM (5) | **Tribal 2 wins**, 3 draws — Military never wins |

**Cross-faction total: Tribal 6 wins, Military 0, 4 draws.**

## Findings, ranked

1. **The Tribal hunter rush decides games before the ritual delay matters.**
   Tribal's first attack lands at ~1.1m (threshold 4); Military's at ~1.3-1.6m
   (threshold 6) with a smaller committed group. In the MT losses the Military
   HQ fell at 1.7-2.0m — BEFORE the 2.5m forcespawn_start. The ritual-spam fix
   was right, but the rush it was masking is the real imbalance.
   *Candidates: Tribal attack_threshold 4→5/6, hunter cost 50→65, or an
   attack_start floor like the harass/ritual ones. The deep fix is the threat
   pass making early cross-map travel expensive for everyone.*

2. **Military can't close a game.** All five mirrors timed out; Military won
   zero cross-faction matches. Post-first-attack it settles into the known
   attrition equilibrium (army ~3, replacing losses 1:1 vs the ecosystem,
   re-attack threshold never re-reached). *Candidates: lower re-attack
   threshold after first commit, or escalating sustain. Also threat-pass-
   coupled — zombies en route are the attrition.*

3. **Corner asymmetry is real and measurable** (Phase 3.5 map-pass input): in
   3 of 5 MM mirrors the PLAYER-corner Military never attacked at all while
   the AI-corner one attacked at ~1.4m — same code, same profile, different
   corner. Infested-building distribution near spawn corners decides economy
   viability. This is exactly the hazard-topology parameterization the map
   pass exists for.

4. **Harassment is rare in practice** (0-2 orders/match): armies rarely hold
   above the attack threshold long enough to peel. Expected to improve with
   any fix to finding 2; don't tune it independently yet.

5. **Rituals fire as designed when a Shaman exists**: 7-10/match at the 45s
   cadence — waves, not a faucet. In 2 of 5 TM matches Tribal never reached a
   Shaman (corner economy again — finding 3).

## What A6 certifies (the Track A exit checklist)
- ✅ Builds, techs, grows economy (workers 0→4 on curve, both factions)
- ✅ Masses to a threshold and commits (first attacks 1.1-1.6m)
- ✅ Defends its base (A2 verified separately; DEFEND posture fires in-match)
- ✅ Harasses (orders fire when army permits; kills verified in A5 run)
- ✅ Plays both factions; matches produce winners (cross-faction)
- ⚠ Mirror stalemates + Tribal dominance = the A6b tuning agenda
- ⏳ "Does it pressure me?" — Matt's feel-test, tonight

*Generated from the 2026-06-10 batch; analysis script inline in the session
log. Raw match JSONLs in user://matches (seeds 411-435).*
