extends Node

# Temporary perf investigation autoload. Prints entity counts and frame-time
# stats every PROBE_INTERVAL seconds. Remove after the perf bug is fixed.
#
# Output is grep-friendly: [PerfProbe t=N.Ns] key=value ...

const PROBE_INTERVAL := 10.0

# Shambler per-system timing (sh_nav_us / sh_sep_us / sh_perc_us /
# sh_prox_us / shambler_total_us). Enabled during the 2026-06-08
# perf-cliff investigation to localize the 1070 ms/tick the standard
# Performance monitors couldn't see; default OFF afterward because the
# Time.get_ticks_usec() calls fire 250 zombies x 60 Hz x time_scale (up
# to 120k calls/sec) and add measurable cost themselves. Flip to true
# when an investigation needs the breakdown.
const DIAG_SHAMBLER_TIMING := false

var _timer: float = 0.0
var _start_time_ms: int = 0
var _frame_count: int = 0
var _frame_time_accum_ms: float = 0.0
var _frame_time_max_ms: float = 0.0

# Shambler hot-path timing accumulators (2026-06-08 hidden-cost hunt).
# Shambler._physics_process adds to these every tick; PerfProbe sums across
# the probe window and resets. Granular enough to localize which sub-call
# (nav, separation, perception, attack/state) is eating the 1070 ms/tick the
# Performance monitors can't see. Reset to zero at every probe.
var shambler_total_us: int = 0
var shambler_nav_us: int = 0
var shambler_sep_us: int = 0
var shambler_perc_us: int = 0
var shambler_proxim_us: int = 0
var shambler_ticks: int = 0


func _ready() -> void:
	_start_time_ms = Time.get_ticks_msec()
	# Print immediately at startup so we have a t=0 baseline.
	_timer = PROBE_INTERVAL


func _process(delta: float) -> void:
	# Track per-frame timing.
	var dt_ms: float = delta * 1000.0
	_frame_time_accum_ms += dt_ms
	_frame_count += 1
	if dt_ms > _frame_time_max_ms:
		_frame_time_max_ms = dt_ms

	_timer -= delta
	if _timer <= 0.0:
		_timer = PROBE_INTERVAL
		_emit_probe()


func _emit_probe() -> void:
	var t_sec: float = (Time.get_ticks_msec() - _start_time_ms) / 1000.0
	var avg_frame_ms: float = (_frame_time_accum_ms / float(_frame_count)) if _frame_count > 0 else 0.0
	var fps_avg: float = 1000.0 / avg_frame_ms if avg_frame_ms > 0 else 0.0

	# Entity counts via group lookups.
	var tree := get_tree()
	var units_n: int = tree.get_nodes_in_group("units").size()
	var player_units_n: int = tree.get_nodes_in_group("player_units").size()
	var ai_units_n: int = tree.get_nodes_in_group("ai_units").size()
	var walkers_n: int = tree.get_nodes_in_group("walkers").size()
	var corpses_n: int = tree.get_nodes_in_group("corpses").size()
	var projectiles_n: int = tree.get_nodes_in_group("projectiles").size()
	var buildings_n: int = tree.get_nodes_in_group("buildings").size()

	# Zombie count via ZombieField (the canonical source).
	var zombies_n: int = 0
	var zf = tree.get_first_node_in_group("zombie_field")
	if zf != null and zf.has_method("get_zombie_count"):
		zombies_n = zf.get_zombie_count()

	# Noise system: active emitter count and total magnitude, plus the
	# attract-tick and occlusion-check timings from the most recent tick.
	# This is the primary perf metric for the building-occlusion hypothesis.
	var noise_emitters_n: int = 0
	var noise_total_intensity: float = 0.0
	var noise_attract_us: int = 0
	var noise_occlusion_us: int = 0
	var noise_occlusion_calls: int = 0
	var noise_occlusion_enabled: bool = true
	var nf = tree.get_first_node_in_group("noise_field")
	if nf != null and "_emitters" in nf:
		var ems = nf._emitters
		noise_emitters_n = ems.size()
		for e in ems:
			noise_total_intensity += e.intensity
		if "_last_attract_us" in nf:
			noise_attract_us = nf._last_attract_us
		if "_last_occlusion_us" in nf:
			noise_occlusion_us = nf._last_occlusion_us
		if "_occlusion_calls_last_tick" in nf:
			noise_occlusion_calls = nf._occlusion_calls_last_tick
		if "_occlusion_enabled" in nf:
			noise_occlusion_enabled = nf._occlusion_enabled

	# DecayField: per-draw cost + active tile count + drawn (post-cull) count.
	# decay_active_tiles is the monotonic total (any tile ever above the draw
	# threshold); decay_drawn is the viewport-culled count actually submitted
	# to the render server. When the camera is unavailable (legacy code path)
	# the two are equal.
	var decay_draw_us: int = 0
	var decay_active_tiles: int = 0
	var decay_drawn: int = 0
	var df = tree.get_first_node_in_group("decay_field")
	if df != null:
		if "_last_draw_us" in df:
			decay_draw_us = df._last_draw_us
		if "_last_active_tiles" in df:
			decay_active_tiles = df._last_active_tiles
		if "_last_drawn" in df:
			decay_drawn = df._last_drawn

	# Godot engine breakdown (2026-06-08 perf-cliff diagnosis): split the
	# raw frame_ms into process-script time vs physics-engine time vs
	# nav-server load. The cliff post-throttle-fix still hits at ~240
	# zombies; this localizes whether the remaining cost is GDScript
	# (perception/separation) vs physics-server (kinematic collisions)
	# vs nav-server (250+ NavigationAgent2D queries).
	var engine_proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var engine_phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	# TIME_NAVIGATION_PROCESS (Godot 4.3+) is the smoking gun for nav-server
	# saturation. Past-cliff probe shows proc+phys = 25ms but frame = 1168ms;
	# the unaccounted 1140ms is suspected to be the NavigationServer running
	# pathfinding for 250+ NavigationAgent2D instances.
	var engine_nav_ms: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var phys_pairs: int = int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	var phys_islands: int = int(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT))
	var nav_agents: int = int(Performance.get_monitor(Performance.NAVIGATION_2D_AGENT_COUNT))
	var nav_active_maps: int = int(Performance.get_monitor(Performance.NAVIGATION_2D_ACTIVE_MAPS))
	var nav_polys: int = int(Performance.get_monitor(Performance.NAVIGATION_2D_POLYGON_COUNT))
	# Node/orphan counts to catch the "queue_free not actually freeing" leak
	# class - if these climb without bound alongside the cliff, something is
	# holding references and the entity count we report from groups undercounts
	# the real cost (orphans still consume Object instance overhead).
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_count: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	# Memory + resource counts (2026-06-08, gradual-leak hunt). User reported
	# interactive sessions crashing after 3-5 min; headless 60s shows no leak,
	# so we need a longer window with memory tracking. mem_mb is the resident
	# Object pool size (Variants etc., main leak indicator); res_count is
	# Resource instance count (textures, sub-resources, etc).
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var obj_count: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var res_count: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))

	# Projectile registry size (includes dead refs - leak indicator).
	var proj_registry_n: int = 0
	if ProjectileManager != null and "_active_projectiles" in ProjectileManager:
		proj_registry_n = ProjectileManager._active_projectiles.size()

	# Squad system: squad count + total tracked members.
	var squads_n: int = 0
	var squad_members_n: int = 0
	if SquadManager != null and SquadManager.has_method("get_all_squads"):
		var sqs = SquadManager.get_all_squads()
		squads_n = sqs.size()
		for s in sqs:
			if s != null and "members" in s:
				squad_members_n += s.members.size()

	print("[PerfProbe t=%.1fs] frames=%d avg_fps=%.1f max_frame_ms=%.1f units=%d players=%d ai=%d walkers=%d zombies=%d corpses=%d projectiles=%d proj_registry=%d buildings=%d noise_emitters=%d noise_total_intensity=%.0f squads=%d squad_members=%d noise_attract_us=%d noise_occlusion_us=%d noise_occlusion_calls=%d noise_occlusion_enabled=%s decay_draw_us=%d decay_active_tiles=%d decay_drawn=%d proc_ms=%.1f phys_ms=%.1f nav_ms=%.1f phys_pairs=%d phys_islands=%d nav_agents=%d nav_maps=%d nav_polys=%d nodes=%d orphans=%d mem_mb=%.1f objs=%d res=%d shambler_us=%d sh_nav_us=%d sh_sep_us=%d sh_perc_us=%d sh_prox_us=%d sh_ticks=%d" % [
		t_sec,
		_frame_count,
		fps_avg,
		_frame_time_max_ms,
		units_n,
		player_units_n,
		ai_units_n,
		walkers_n,
		zombies_n,
		corpses_n,
		projectiles_n,
		proj_registry_n,
		buildings_n,
		noise_emitters_n,
		noise_total_intensity,
		squads_n,
		squad_members_n,
		noise_attract_us,
		noise_occlusion_us,
		noise_occlusion_calls,
		str(noise_occlusion_enabled),
		decay_draw_us,
		decay_active_tiles,
		decay_drawn,
		engine_proc_ms,
		engine_phys_ms,
		engine_nav_ms,
		phys_pairs,
		phys_islands,
		nav_agents,
		nav_active_maps,
		nav_polys,
		node_count,
		orphan_count,
		mem_mb,
		obj_count,
		res_count,
		shambler_total_us,
		shambler_nav_us,
		shambler_sep_us,
		shambler_perc_us,
		shambler_proxim_us,
		shambler_ticks,
	])
	# Reset hot-path accumulators so the next probe window shows fresh data.
	shambler_total_us = 0
	shambler_nav_us = 0
	shambler_sep_us = 0
	shambler_perc_us = 0
	shambler_proxim_us = 0
	shambler_ticks = 0
	# Reset window stats so the next probe shows fresh data.
	_frame_count = 0
	_frame_time_accum_ms = 0.0
	_frame_time_max_ms = 0.0
