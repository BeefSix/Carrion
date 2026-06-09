# THE LONG WAKE — AI Workflow Playbook

*Compiled 2026-06 from a deep-research pass on Claude Code, Claude prompting, PixelLab, and AI-orchestration meta. Tailored to this stack: solo dev, Godot 4 / GDScript, determinism-critical, Claude Code as executor, PixelLab + Gemini for art, the three-layer (design / execute / verify) loop. **[O]** = official Anthropic/PixelLab docs; **[C]** = community/practitioner.*

---

## DO THESE FIRST — the 6 changes that will actually move your outcomes

1. **Convert your verification rules from prompts into HOOKS.** CLAUDE.md is delivered as a *user message with no compliance guarantee* — "looks done" is the only signal Claude has unless you give it a check it can run [O]. Right now you (and I, by re-typing it every prompt) are the verification loop. A **Stop hook** that runs `godot --headless --check-only` and **blocks the turn from ending until it passes** makes your parse-check *enforced*, not hoped-for. A **PostToolUse hook** on `Edit|Write` can run it after every edit. This single change removes the most repetitive thing in our whole workflow. (Hook exit code 2 = block + feed stderr back to Claude so it fixes and continues.) [O]

2. **Add a "determinism-reviewer" subagent (AI reviews AI).** A read-only subagent whose only job is to grep new/changed gameplay code for your forbidden patterns — bare `randf()`/`randi()`, transcendentals (`sin`/`cos`/`atan2`/inverse-sqrt) in sim math, `get_nodes_in_group()` where order matters, `_process(delta)` mutating sim state, whole-file rewrites — and report violations before you review. This automates exactly the audit I've been doing by hand. Runs in its own context (Haiku/Sonnet, cheap), returns a summary. [O]

3. **Fix PixelLab roster style-drift with a palette-lock pass.** Your stated #1 art pain. The gotcha: **the PixelLab MCP does NOT expose hard color-locking** — only the web/Aseprite UIs do [O]. The reliable path from Claude Code: **generate via MCP → run everything through the Reduce-Colors / quantization tool against ONE canonical Lospec palette** (your faction palettes). This is the single biggest fix for "my roster looks inconsistent." Also: **reuse the same `seed`** across a related batch, and use **`create_character_state`** for "same unit, different equipment/team color" (it keeps identity + proportions across all rotations) — perfect for faction tints and doctrine variants. [O]

4. **Add Context7 MCP to Claude Code.** It serves version-pinned real Godot 4.x docs into the agent, killing API hallucination [C]. Given how many Godot-version-specific bugs we hit (iso autotiling, the `--check-only` autoload false-positives, the physics layer behavior), keeping Claude Code honest about the actual current API is high-value.

5. **Set effort to `xhigh` and route models.** On Opus 4.8, **`xhigh` is the recommended default for coding/agentic work** [O]. If Claude under-uses tools or under-spawns subagents, **raise effort — don't add aggressive "you MUST" wording** (Opus 4.8 over-corrected the old under-triggering; aggressive language now backfires) [O]. Use **`opusplan`** (Opus for planning, auto-Sonnet for code-gen), and route grunt subagents (parse-checks, AUDIT bookkeeping) to **Haiku**. [O/C]

6. **Cache your big context.** Your CLAUDE.md + DESIGN_MASTER.md + AUDIT.md + NETCODE.md get re-sent every session — prompt caching is ~90% off on cache reads and pays for itself after one reuse [O]. Big recurring cost win for heavy daily use.

---

## 1. Claude Code — power-user levers

- **CLAUDE.md hierarchy + the 200-line rule.** Files load broadest→specific and *concatenate*; keep each **under 200 lines** — bloat actively *reduces* instruction adherence ("rules lost in noise") [O]. Your current docs are good; watch the length.
- **`.claude/rules/*.md` with `paths:` frontmatter** — scope instructions to file globs so they load *only* when Claude touches matching files. The modern way to keep a big project's rules out of every session's context. E.g. a `determinism.md` rule scoped to `scripts/**` [O].
- **Skills replaced custom slash commands** (2026). `.claude/skills/<name>/SKILL.md` with `description` (key use case first), `allowed-tools` (pre-approve commands), `context: fork` + `agent: Explore` (run in a subagent), and **dynamic injection** via `` !`git diff HEAD` `` (runs the shell command and inlines output before Claude sees the skill) [O]. Build a committed library of your common ops (audit, fix-batch, feel-test-checklist).
- **Subagents = context isolation.** Each runs in its own window; verbose output (test logs, searches) stays there, only a summary returns — the primary defense against context rot [O]. Frontmatter: `tools`/`disallowedTools`, `model`, `mcpServers` (scope an MCP to one subagent to keep its tool defs out of main context), `isolation: worktree`, `effort`, `background: true`. Subagents **can't spawn subagents** — orchestrate from the main thread.
- **`/fork`** — a subagent that inherits the full conversation (shares prompt cache, cheaper) instead of starting fresh; good for "try two approaches" [O].
- **Context discipline:** `/clear` aggressively between unrelated tasks; **the 2-correction rule** — if you've corrected Claude twice on the same thing, the context is polluted with failed approaches; `/clear` + a better prompt beats a long session every time [O]. Don't push past ~90% or let auto-compact fire mid-task [C].
- **Plan mode** (`Shift+Tab` cycles) for any multi-file change; `Ctrl+G` opens the plan in your editor to hand-edit before execution. Skip it for one-sentence diffs [O].
- **Checkpoints / `/rewind` (`Esc Esc`)** — auto-saved before every change; restore code, conversation, or both. Lets you take bigger swings safely (not a git replacement) [O].
- **Newer features:** Plugins + marketplaces (one-command bundles of commands+agents+MCP+hooks), Sandboxing + `auto` permission mode (OS-level isolation, fewer prompts), Claude Code on the web, experimental Agent Teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) [O].

## 2. The verification ladder (formalize what we do by hand)

Anthropic's escalation, hardest-gating last [O]:
1. **In one prompt** — "run the check and iterate in the same message."
2. **`/goal` condition** — a separate evaluator re-checks every turn until it holds.
3. **Stop hook** — runs your check as a script, blocks the turn from ending until it passes (overrides after 8 blocks). ← *the strong one for your parse-check.*
4. **Verification subagent** — a fresh model tries to *refute* the result, so the worker isn't grading itself. ← *your determinism reviewer + diff review.*

Rules: **demand evidence, not "done"** (the test output, the command + result, a screenshot). **"If you can't verify it, don't ship it."** For diff review, scope the reviewer to *correctness/requirement gaps only* — "report gaps, not style preferences" — because a reviewer told to find issues always will, and chasing all of them causes over-engineering [O]. (This is exactly the failure I avoid by note-don't-fix.)

## 3. Claude prompting — what changed in 2026

- **`effort` (low/medium/high/xhigh/max) replaced `budget_tokens`** (deprecated). **Prefilling the assistant turn is gone** (400 error on 4.6+) — drop any "prefill `{` for JSON" tricks [O].
- **Opus 4.8 follows instructions literally and doesn't auto-generalize** — if a rule should apply broadly, **state the scope** ("apply to every section, not just the first"). Great for predictable pipelines [O].
- **It's sensitive to the word "think" when thinking is off** — use "consider/evaluate/reason through" [O].
- **Overthinking is now a real failure mode** at high effort — counter with "choose an approach and commit; don't revisit unless new info contradicts" [O].
- **Anti-over-engineering snippet** (add to your agent config — it maps 1:1 onto your "targeted edits only" rule): *"Only make changes directly requested or clearly necessary. A bug fix doesn't need surrounding code cleaned up. Don't add error handling for scenarios that can't happen. Don't create abstractions for one-time operations."* [O]
- **`<investigate_before_answering>`:** *"Never speculate about code you have not opened. If the user references a file, read it before answering."* — reinforces your verify contract [O].
- **Honest/critical output:** separate *finding* from *filtering* — "report every issue including low-severity/uncertain ones; don't filter for importance at this stage." Anthropic has trained sycophancy down (~half in 4.7 vs 4.6) [O].
- **Long docs:** put them at the TOP (queries-at-end can be +30% quality), wrap in XML, and **ask for relevant quotes first** (also the #1 hallucination reducer) [O].

## 4. PixelLab — advanced techniques & gotchas

- **Non-blocking fan-out is the #1 throughput win.** Every create-tool returns a job ID *immediately* (jobs run 2–5 min in background). Queue a character + all its animations + all tileset terrains *without waiting*, then batch the `get_*` calls [O].
- **`base_tile_id` chaining** keeps multi-terrain sets continuous (Ocean→Beach→Grass→Forest): the first tileset returns base IDs, pass them to the next [O].
- **Read the Godot MCP resources before wiring tiles.** `pixellab://docs/godot/wang-tilesets` includes a **headless GDScript converter** that produces the `.tres` TileSet with correct terrain/peering bits — have Claude Code read it instead of hand-rolling atlas/bitmask setup. Also `.../isometric-tiles` and `.../sidescroller-tilesets` [O].
- **Prompt the MIDDLE of the tile, not the whole scene** — the model is trained per-tile off the selection center [O]. Identity → `description`; pose/blend/palette → the separate *options*; don't overload the prompt. `text_guidance_scale` (default 8) is the "follow my prompt literally" dial [O].
- **Small sprites ≤16px are weak** (documented #1 limitation) — generate larger and downscale, especially for many small RTS unit sprites [O].
- **Init-image strength bands:** 0–300 color only / 300–400 rough shapes / 400–600 variations / 600–900 add-detail-to-near-final. Start low, ratchet up as you converge [O].
- **Characters persist; objects/map-objects auto-delete in 8h** — build your roster as *characters* for persistence [O].
- **Credit model:** basic = 1 credit, Pro models = **40 credits**; cost scales with size via the frame grid (smaller = more frames/credit). Call `get_balance` before big batches; leave `confirm_cost=false` until checked [O/C]. Indie budget ~2–3k credits/mo [C].
- **Surface inequality:** Aseprite gets features first and exposes the deepest controls (force-colors, full skeleton editor, inpaint layers); **MCP is a curated subset** [O]. Hybrid workflow: **MCP from Claude Code for bulk generation + Godot wiring; Aseprite for palette-lock + skeleton + cleanup; Sprite Fusion for map assembly.**
- **No isometric autotiling/Wang** (confirms ART_PIPELINE_RESEARCH.md) — iso is per-tile; seamless iso terrain is manual or via the render-to-iso pipeline.

## 5. Orchestration / meta

- **Git worktrees + `isolation: worktree` subagents** — true parallel work without file collisions; say "work in a worktree" or set it in subagent frontmatter. **Practical cap 2–4** (you become the review bottleneck, not Claude). Wire a weekly `git worktree prune` [O/C].
- **MCP stack for this project:** Godot MCP (headless run + your parse gate), PixelLab MCP (sprites/tiles), **Context7** (Godot 4.x API truth), Exa/Brave (search). Manage via Docker MCP Toolkit for container isolation if the list grows. **Add servers deliberately** — each one burns context on tool defs and adds attack surface [C].
- **Cost stacking (each independent, they multiply):** model routing (Haiku for grunt, ~30–40% off), prompt caching (~90% off reuse), scoped prompts with exact file paths (~30–50% fewer search tokens — point at `IsoView.gd`, don't let it grep), Batch API (flat 50% off for non-urgent bulk like AUDIT verification sweeps) [O/C].
- **Reality check on the hype:** A2A protocol, "swarms"/blackboard, 48-agent "studios" — real for enterprises, **not load-bearing for a determinism-constrained solo game sim.** The honest assessment even from the 48-agent demos: a solo dev with orchestration ≈ "a solo dev with two or three experienced collaborators," not a 48-person studio. Treat as inspiration, not blueprint [C]. The recurring lesson across every solo-builder case study: **the skill is orchestration, not prompting** — which is exactly the three-layer loop you're already running.

---

## The one-paragraph version

You're already running the orchestration pattern the whole industry converged on (plan → execute → verify → checkpoint, three layers, AI-reviews-AI). The upgrade is to **stop doing the verification by hand**: make the parse-check a **Stop hook**, make the determinism audit a **reviewer subagent**, fix PixelLab consistency with a **palette-quantization pass against one Lospec palette**, add **Context7** so the agent stops guessing Godot APIs, run at **`xhigh` effort** with **model routing + prompt caching** for cost, and lean on **worktrees** when you parallelize. Everything else is refinement.
