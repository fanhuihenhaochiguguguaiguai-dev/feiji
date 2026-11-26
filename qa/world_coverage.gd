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
		var seed_id := int(sector.seed)
		WORLD.prepare_relief(seed_id)
		var fine_index := WORLD.fine_tile_index(seed_id)
		var decode_us := 0
		var generate_us := 0
		var error_m := 0.0
		for coord in fine_index:
			var started := Time.get_ticks_usec()
			var loaded := WORLD.read_tile(coord, seed_id, fine_index)
			decode_us += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			var baked := WORLD.bake_tile(coord, seed_id)
			generate_us += Time.get_ticks_usec() - started
			for i in baked.size():
				error_m = maxf(error_m, absf(loaded[i] - baked[i]))
		map.configure(sector, eye, start)
		if not map.resident:
			map._add_resident_ground()
		var seam_error := _coverage_seams(map.resident)
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
		success = success and fine_index.size() == 50 and error_m <= 0.03125 and seam_error <= 0.001
		failures += int(not success)
		summary.append({"theatre": sector.id, "speed_mps": stride.length(), "distance_m": stride.length() * 2400.0 / 90.0,
			"coverage_gaps":coverage_gaps, "rebases":rebases, "mask_matches_fine_tiles":aligned,
			"max_coverage_seam_error_m":seam_error, "offline_tiles":fine_index.size(),
			"max_codec_error_m":error_m, "decode_ms":float(decode_us) * 0.001 / maxi(1, fine_index.size()),
			"generate_ms":float(generate_us) * 0.001 / maxi(1, fine_index.size()), "max_follow_ms":worst_usec * 0.001})
		map.queue_free()
		eye.queue_free()
		await process_frame
	print(JSON.stringify({"terrain":summary,"failures":failures}))
	quit(int(failures > 0))

func _coverage_seams(ground: Node3D) -> float:
	var error := 0.0
	for row in [1, 2]:
		for x in [0, 2]:
			error = maxf(error, _edge_error(ground.get_child(row * 4 + x).mesh, ground.get_child(row * 4 + x + 1).mesh, true))
	for column in [1, 2]:
		for z in [0, 2]:
			error = maxf(error, _edge_error(ground.get_child(z * 4 + column).mesh, ground.get_child((z + 1) * 4 + column).mesh, false))
	return error

func _edge_error(a: ArrayMesh, b: ArrayMesh, across_x: bool) -> float:
	if a.get_surface_count() == 0 or b.get_surface_count() == 0:
		return 0.0
	var left: PackedVector3Array = a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var right: PackedVector3Array = b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var le := roundi(sqrt(left.size())) - 1
	var re := roundi(sqrt(right.size())) - 1
	var edge_steps := maxi(le, re)
	var maximum := 0.0
	for i in edge_steps + 1:
		var left_step := i * float(le) / edge_steps
		var right_step := i * float(re) / edge_steps
		var a0 := _edge_vertex(left, le, floori(left_step), across_x, true)
		var a1 := _edge_vertex(left, le, ceili(left_step), across_x, true)
		var b0 := _edge_vertex(right, re, floori(right_step), across_x, false)
		var b1 := _edge_vertex(right, re, ceili(right_step), across_x, false)
		maximum = maxf(maximum, a0.lerp(a1, fposmod(left_step, 1.0)).distance_to(b0.lerp(b1, fposmod(right_step, 1.0))))
	return maximum

func _edge_vertex(vertices: PackedVector3Array, edge: int, i: int, across_x: bool, end: bool) -> Vector3:
	var boundary := edge if end else 0
	return vertices[i * (edge + 1) + boundary] if across_x else vertices[boundary * (edge + 1) + i]
