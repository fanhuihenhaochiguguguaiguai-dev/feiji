extends SceneTree

const WORLD = preload("res://game/world.gd")
const DATA = preload("res://game/catalogue.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var failures := 0
	var summary := []
	for sector in DATA.new().source.theatres:
		var map := WORLD.new()
		var eye := Camera3D.new()
		root.add_child(eye)
		root.add_child(map)
		var start := Vector3(11450, 3100, 5150)
		map.configure(sector, eye, start)
		if not map.resident:
			map._add_resident_ground()
		var position := map.local_position(start)
		var stride := Vector3(397, 0, -267)
		var coverage_gaps := 0
		var rebases := 0
		var worst_usec := 0
		for i in 2400:
			position += stride / 90.0
			var before := Time.get_ticks_usec()
			var delta := map.follow(position, stride)
			position -= delta
			worst_usec = maxi(worst_usec, Time.get_ticks_usec() - before)
			if delta != Vector3.ZERO:
				rebases += 1
			var cell := map.cell(position)
			var index := cell - WORLD.RESIDENT_MIN
			var resident := index.x >= 0 and index.y >= 0 and index.x < WORLD.RESIDENT_SIDE and index.y < WORLD.RESIDENT_SIDE
			if not map.current.has(cell) and not resident:
				coverage_gaps += 1
			if i % 25 == 0:
				await process_frame
		var offset := Vector3(-map.origin.x * WORLD.TILE, 0.0, -map.origin.y * WORLD.TILE)
		var aligned := map.resident.position.is_equal_approx(offset)
		for tile: Vector2i in map.current:
			var index := tile - WORLD.RESIDENT_MIN
			if index.x >= 0 and index.y >= 0 and index.x < WORLD.RESIDENT_SIDE and index.y < WORLD.RESIDENT_SIDE:
				aligned = aligned and map.residency.get_pixelv(index).r > 0.5
		var success := aligned and rebases > 0 and coverage_gaps == 0 and map.resident.get_child_count() == 16
		failures += int(not success)
		summary.append({"theatre": sector.id, "speed_mps": stride.length(), "distance_m": stride.length() * 2400.0 / 90.0,
			"coverage_gaps": coverage_gaps,"rebases":rebases,"mask_matches_fine_tiles":aligned, "max_follow_ms":worst_usec * 0.001})
		map.queue_free()
		eye.queue_free()
		await process_frame
	print(JSON.stringify({"terrain":summary,"failures":failures}))
	quit(int(failures > 0))
