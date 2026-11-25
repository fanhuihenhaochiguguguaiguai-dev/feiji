extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const STEP := 1.0 / 90.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var db := Data.new()
	var profile := Profile.new(db)
	var fight := Battle.new()
	root.add_child(fight)
	fight.setup(db, profile, "free", {"name":"自由空战","region":0}, false)
	fight.set_physics_process(false)
	fight.set_process(false)
	var worst := 0.0
	var active_tiles := 0
	var cached_tiles := 0
	var samples := []
	var prior := Time.get_ticks_msec()
	var completed := []
	fight.finished.connect(func(value): completed.append(value))
	for step in range(roundi(fight.FREE_LENGTH / STEP)):
		var started := Time.get_ticks_usec()
		if step % 680 == 0:
			fight.action.boost = true
		fight._physics_process(STEP)
		if step % 90 == 0:
			fight.effects.tick(0.08, fight.shots, fight.camera)
			await process_frame
		if step > 360 and step % 450 == 0:
			samples.append(Performance.get_monitor(Performance.MEMORY_STATIC))
		worst = maxf(worst, (Time.get_ticks_usec() - started) * 0.001)
		active_tiles = maxi(active_tiles, fight.world.current.size())
		cached_tiles = maxi(cached_tiles, fight.world.cache.size())
	var outcome := {
		"recorded_mode":"free",
		"physics_seconds":fight.time,
		"wall_time_ms":Time.get_ticks_msec() - prior,
		"player_distance_m":fight.miles,
		"end_roster":fight.fleet.size(),
		"countdown_settlements":completed.size(),
		"total_kills":fight.fleet.reduce(func(count, jet): return count + jet.kills, 0),
		"total_deaths":fight.fleet.reduce(func(count, jet): return count + jet.deaths, 0),
		"max_resident_regions":active_tiles,
		"max_cached_regions":cached_tiles,
		"peak_tick_including_yields_ms":worst,
		"gds_cpu_bytes_at_5_second_intervals":samples,
		"last_origin":[fight.world.origin.x,fight.world.origin.y]
	}
	print(JSON.stringify(outcome, "\t"))
	var ok: bool = fight.fleet.size() == 12 and completed.size() == 1 and outcome.total_kills > 0 and active_tiles < 55 and cached_tiles < 65
	fight.queue_free()
	await process_frame
	quit(0 if ok else 1)
