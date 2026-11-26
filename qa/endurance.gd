extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const STEP := 1.0 / 90.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var matches := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--matches="):
			matches = clampi(int(arg.trim_prefix("--matches=")), 1, 6)
	var catalogue := Data.new()
	var profile := Profile.new(catalogue)
	var results := []
	var ok := true
	for i in matches:
		seed(1822026 + i)
		var result := await _match(catalogue, profile)
		results.append(result)
		ok = ok and result.end_roster == 12 and result.countdown_settlements == 1 and result.total_kills > 0
		ok = ok and result.resident_regions <= 55 and result.cached_regions < 66
	print(JSON.stringify({"matches":results,"simulated_seconds":matches * 600}, "\t"))
	quit(0 if ok else 1)

func _match(catalogue: RefCounted, profile: RefCounted) -> Dictionary:
	var fight := Battle.new()
	root.add_child(fight)
	fight.setup(catalogue, profile, "free", {"name":"无限空战","region":0}, false)
	fight.set_physics_process(false)
	fight.set_process(false)
	var timings := PackedInt64Array()
	var active_tiles := 0
	var cached_tiles := 0
	var samples := []
	var prior := Time.get_ticks_msec()
	var completed := []
	fight.finished.connect(func(value): completed.append(value))
	for step in roundi(fight.FREE_LENGTH / STEP):
		var started := Time.get_ticks_usec()
		if step % 680 == 0:
			fight.action.boost = true
		elif step % 680 == 189:
			fight.action.erase("boost")
		fight._physics_process(STEP)
		timings.append(Time.get_ticks_usec() - started)
		if step % 90 == 0:
			fight.effects.tick(0.08)
			await process_frame
		if step > 360 and step % 900 == 0:
			samples.append(Performance.get_monitor(Performance.MEMORY_STATIC))
		active_tiles = maxi(active_tiles, fight.world.current.size())
		cached_tiles = maxi(cached_tiles, fight.world.cache.size())
	timings.sort()
	var outcome := {
		"physics_seconds":fight.time, "wall_time_ms":Time.get_ticks_msec() - prior,
		"distance_m":fight.miles, "end_roster":fight.fleet.size(),
		"countdown_settlements":completed.size(),
		"total_kills":fight.fleet.reduce(func(count, jet): return count + jet.kills, 0),
		"total_deaths":fight.fleet.reduce(func(count, jet): return count + jet.deaths, 0),
		"resident_regions":active_tiles, "cached_regions":cached_tiles,
		"physics_step_ms_p50":timings[int(timings.size() * 0.50)] / 1000.0,
		"physics_step_ms_p99":timings[int(timings.size() * 0.99)] / 1000.0,
		"physics_step_ms_max":timings[-1] / 1000.0,
		"resident_cpu_bytes_samples":samples,
	}
	fight.queue_free()
	await process_frame
	outcome["post_battle_cpu_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
	return outcome
