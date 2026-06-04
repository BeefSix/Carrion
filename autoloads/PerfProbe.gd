extends Node

# Temporary perf investigation autoload. Prints entity counts and frame-time
# stats every PROBE_INTERVAL seconds. Remove after the perf bug is fixed.
#
# Output is grep-friendly: [PerfProbe t=N.Ns] key=value ...

const PROBE_INTERVAL := 30.0

var _timer: float = 0.0
var _start_time_ms: int = 0
var _frame_count: int = 0
var _frame_time_accum_ms: float = 0.0
var _frame_time_max_ms: float = 0.0


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

	# Noise system: active emitter count and total magnitude.
	var noise_emitters_n: int = 0
	var noise_total_intensity: float = 0.0
	var nf = tree.get_first_node_in_group("noise_field")
	if nf != null and "_emitters" in nf:
		var ems = nf._emitters
		noise_emitters_n = ems.size()
		for e in ems:
			noise_total_intensity += e.intensity

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

	print("[PerfProbe t=%.1fs] frames=%d avg_fps=%.1f max_frame_ms=%.1f units=%d players=%d ai=%d walkers=%d zombies=%d corpses=%d projectiles=%d proj_registry=%d buildings=%d noise_emitters=%d noise_total_intensity=%.0f squads=%d squad_members=%d" % [
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
	])
	# Reset window stats so the next probe shows fresh data.
	_frame_count = 0
	_frame_time_accum_ms = 0.0
	_frame_time_max_ms = 0.0
