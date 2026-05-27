# CARRION — Prototype Plan

**The one question this answers:** when I play Military and then play Tribal on the same map, do they feel like fundamentally different games — and is the noise/zombie/decay loop interesting enough that I want to keep playing? Everything below is in service of that question and nothing else.

**Two-faction unit picks** (chosen because each pair maximally exposes the asymmetric thesis):

- **Military:** Looter (loud gather), Rifleman (loud combat), Heavy Gunner (very loud, AoE — this is what makes noise feel real)
- **Tribal:** Walker (zombie-immune gather), Hunter (silent ranged), Shaman (force-spawn ability — this is what makes Tribal feel *different*, not just "Military but quiet")

**Single resource:** call it Salvage. Both factions use it for everything. Yes, this collapses ammo/food/scrap/water/ritual into one number; that's the point — you're not testing the economic friction, you're testing the asymmetric *behavior*.

---

## Week 1 — Military gathers in a sandbox

1. **Godot 4 project init.** New repo, top-down 2D, 60Hz fixed tick, programmer-art placeholder sprites (colored squares with letters).
2. **Static map.** 80×80 tile grid, one visual ground texture, no fog, no terrain variation.
3. **RTS camera.** WASD pan, scroll zoom, bounded to map.
4. **Unit base class.** HP, position, faction tag, current command. Render as colored square with HP bar.
5. **Selection.** Left-click single-select, left-click-drag box-select, selection ring visible.
6. **Movement.** Right-click move using Godot's `NavigationAgent2D` and `NavigationRegion2D`. Don't roll your own A*.
7. **Resource HUD.** Top-bar Salvage counter. Starts at 200.
8. **HQ building (Command Post).** Footprint, HP, production queue UI, rally point. Click to queue Looter.
9. **Looter unit.** Stats from §7.1 (HP 60, speed 3.0). Right-click a lootable building → walk there → channel 3 sec → return to HQ → deposit → repeat.
10. **Lootable buildings.** Place ~30 across the map at startup with 200 Salvage each. Despawn when empty.

**End of Week 1:** A small map where Military Looters gather Salvage. That's it. No combat, no zombies. Validate that the core RTS feel works before adding anything novel.

---

## Week 2 — Zombies make the map an opponent

11. **Shambler zombie.** HP 40, speed 1.5, melee 8. Wanders when idle; pathfinds toward target when one exists.
12. **Infested buildings.** Mark ~15 buildings on map as infested. Each spawns one Shambler every 60 sec (modified later).
13. **Aggro priority.** Shamblers target nearest non-Tribal unit within 12-tile vision. (Tribal tag doesn't exist yet — wire the check now so Week 3 plugs in cleanly.)
14. **Noise events.** Every attack, loot action, and Heavy Gunner shot emits a `NoiseEvent(position, magnitude)` per §9.4 values.
15. **Noise field.** Coarse 16-tile cell grid, accumulate noise, decay 5/sec. Debug heatmap overlay toggleable with F4.
16. **Horde trigger.** When a cell crosses 250 cumulative noise, spawn 25 Shamblers from nearest map edge, pathing to the noise center.
17. **Barracks.** Build with Looter (placed by player), 50 sec construction, gates Rifleman and Heavy Gunner.
18. **Rifleman.** §7.1 stats. Auto-attack hostiles in range. Right-click attack command.
19. **Heavy Gunner.** §7.1 stats. AoE damage, 50 noise/sec while firing. Tune the noise number until firing it for 5 sec triggers a horde — this is the moment the player learns the game has weight.
20. **Death & corpses.** Killed unit drops a corpse with a 90-sec timer.
21. **Enhanced returns.** Timer expires → corpse becomes a Shambler with the original unit's HP. Yes, your own dead Rifleman becomes a tougher zombie that walks back to attack you. This is the soul of the game; do not skip it.

**End of Week 2:** Military faction in a survival sandbox. Play it for 20 minutes. **First feel check:** does firing the Heavy Gunner feel like a *decision* with consequences, or just an attack? If it doesn't, stop and tune before continuing — that signal is everything.

---

## Week 3 — Tribal makes the asymmetry real

22. **Faction tag wired through aggro.** Tribal units are invisible to the zombie aggro check from step 13. Test by spawning a unit with Tribal tag and watching Shamblers walk past.
23. **Tribal Camp (HQ).** Same as Command Post mechanically, different sprite color. Produces Walkers.
24. **Walker unit.** Stats from §7.3. Gathers from lootable buildings exactly like Looter, but generates 0 noise.
25. **Hunting Lodge.** Production building. Gates Hunter.
26. **Hunter unit.** §7.3 stats. Silent ranged attack (noise 1, basically nothing). Has to actually *aim and kill* zombies one at a time rather than pulling waves.
27. **Ritual Site.** Production building. Gates Shaman.
28. **Shaman unit + force-spawn.** Right-click an infested building with Shaman selected → channel 5 sec, spend 25 Salvage → 4 Shamblers spawn from that building. Spawned zombies have a `tribal_aligned` flag.
29. **Tribal-aligned zombie behavior.** These shamblers don't aggro Tribal and do aggro Military. They wander otherwise. (No need for direct control — just point-and-release.)
30. **Pre-match faction picker.** Title screen with two buttons: Military or Tribal. Sandbox starts with that faction.

**End of Week 3:** Play Tribal sandbox for 20 minutes. Then play Military sandbox for 20 minutes. **Second feel check:** do these feel like *different games* or like the same game with reskinned units? If they feel the same, the asymmetry isn't deep enough — this is the moment to add weight to either Heavy Gunner's noise or Shaman's force-spawn before continuing.

---

## Week 4 — Decay and an actual match

31. **Decay tile state.** Per-tile float 0–150. Renders as red-brown discoloration overlay scaled by value.
32. **Decay accumulation.** Each active Military structure adds 0.1/sec to tiles within its radius, expanding +0.5 tiles/min up to 12. Survivor Engineer sanitation: not implemented (no Survivors).
33. **Decay effects on spawning.** Infested buildings in decayed tiles spawn 2× as fast at 50+ decay, 3× at 100+. Verify by parking a Heavy Gunner near a Military base for 5 min and watching the spawn pattern.
34. **Cremation.** Any combat unit can right-click a corpse to channel 4 sec and destroy it. Required so the player has *agency* over the return cycle.
35. **Two-faction map.** Pre-place a Command Post in the NW corner and a Camp in the SE corner. Both factions exist on the map at match start.
36. **Inert opposing faction.** The faction you're not playing just sits there — its HQ exists, it has no units, it does nothing. Sufficient to test "can I destroy their HQ" mechanically.
37. **HQ destruction = win.** Opposing HQ HP hits 0 → "Victory" screen with restart button. Your HQ destroyed → "Defeat."

**End of Week 4:** You can pick a faction, walk across the map, and destroy the other faction's HQ. That's a "match." It's not a good one yet.

---

## Week 5 — Real matches via hot-seat

38. **Hot-seat mode.** F1 toggles which faction the camera/selection is controlling. Both factions run simultaneously; you alternate turns of 90 sec each (timer in HUD) or freely switch — try both and see which is more playable. Hot-seat is better than a dumb AI here because you experience both sides directly, which is exactly what the prototype is testing.
39. **Match start state.** Each faction starts with 1 HQ + 2 workers + 1 combat unit + 300 Salvage. Symmetric starting positions.
40. **Tuning pass: noise.** Play 3 hot-seat matches. Adjust noise thresholds and Heavy Gunner noise/sec until firing Heavy Gunners feels meaningful but not suicidal.
41. **Tuning pass: economy.** Adjust Looter/Walker gather rates and unit costs until both factions can reach combat-readiness in 5–8 min.
42. **Tuning pass: decay.** Adjust decay growth rate until a 15-min Military base produces a decay zone Tribal can actually exploit.
43. **Tuning pass: force-spawn.** Adjust Shaman cost and spawn count until force-spawn feels powerful but not auto-win.

**End of Week 5:** Hot-seat matches lasting 20–40 minutes that feel like a real game.

> **Architect note (added 2026-05-27):** "feels meaningful but not suicidal" is the kind of feedback that takes 10+ play sessions to settle, not one. Budget for that — Week 5 may really be Weeks 5-6, and Week 6 slides to 7. That's fine. Don't compress tuning to hit the calendar.

---

## Week 6 — Verdict

44. **Play 10 matches.** Keep a notebook. After each, write 2 sentences: what felt good, what felt bad.
45. **Identify the top 3 feel issues.** Fix them or document why you can't.
46. **Decision document.** One page, three sections:
   - **Is it fun?** Yes / No / Could be with X.
   - **Does the asymmetry work?** When you played Military vs Tribal, were you making *different decisions* — not just using different tools to make the same decisions?
   - **Verdict.** Commit to the full plan / pivot / shelve.

---

## What you're actually playtesting for

These are the specific signals that tell you the thesis is alive:

1. **Heavy Gunner anxiety.** When the Military player fires the Heavy Gunner, do they *hesitate* because of the noise consequence? If yes, the noise system works. If they fire freely, noise is undertuned.
2. **Walker wonder.** First time you watch a Walker stroll calmly past a pack of zombies, does it feel weird and exciting? If yes, the zombie-immunity asymmetry lands. If it feels like nothing, that asymmetry isn't visually selling itself.
3. **Decay regret.** Does the Military player look at the growing red zone around their base and feel like they're *paying* for their power? Or does it feel like cosmetic terrain?
4. **Shaman power-fantasy.** When the Tribal player force-spawns four shamblers into Military territory, does it feel like a *weapon* — different from just having more units? If force-spawn feels like "small attack," it's failing.
5. **Cross-faction itch.** After 5 matches as Military, do you want to play Tribal *to see how it solves the same map differently*? Or do you want another match of Military to optimize? The first response is the thesis working. The second is the thesis failing.

**Red flags that mean rethink before Phase 1 of the full plan:**

- Matches end in under 10 minutes consistently → economy/combat too fast, the strategic systems don't get to express
- Matches drag past 60 minutes → no pressure to commit, win condition too lax
- One faction wins ~80% of hot-seat matches → core asymmetric balance broken; not a tuning problem, a design problem
- You stop firing Heavy Gunners entirely / stop using force-spawn → those mechanics aren't worth their cost, the design's central tension isn't pulling its weight

---

## Prototype discipline — commit upfront

- **No art passes.** Colored squares with letters (`L` for Looter, `R` for Rifleman, `S` for Shaman) the whole way. The temptation to "just spend an afternoon on sprites" is the prototype-killer.
- **No menus.** Press a key to start Military, another for Tribal, another for hot-seat. Real UI is Phase 1 of the full plan.
- **No sound.** Adds nothing to the question being answered.
- **One map.** Same 80×80 every match. Variety is a Phase 9 problem.
