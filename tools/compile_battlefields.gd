extends SceneTree

const WORLD = preload("res://game/world.gd")
const DATA = preload("res://game/catalogue.gd")
const BATTLE = preload("res://game/battle.gd")
const SPACING := 384.0
const EDGE := int(WORLD.RESIDENT_SIDE * WORLD.TILE / SPACING) + 1
const PATCH := 48
const OUTPUT := "res://assets/environment"

func _initialize() -> void:
	call_deferred("compile")

func compile() -> void:
	for theatre in DATA.new().source.theatres:
		var seed_id := int(theatre.seed)
		WORLD.prepare_relief(seed_id)
		if not _compile_detail(seed_id):
			push_error("Could not save fine terrain for %d" % seed_id)
			quit(1)
			return
		if "--detail-only" in OS.get_cmdline_user_args():
			continue
		var origin := Vector2(WORLD.RESIDENT_MIN) * WORLD.TILE
		var heights: PackedFloat32Array = ClassDB.class_call_static("SkyTerrainKernel", "height_tile",
			origin.x, origin.y, EDGE, SPACING, seed_id)
		var ground := Node3D.new()
		for z in range(0, EDGE - 1, PATCH):
			for x in range(0, EDGE - 1, PATCH):
				var chunk := MeshInstance3D.new()
				chunk.mesh = _patch(heights, origin, x, z, bool(theatre.snow), seed_id == 116)
				chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				ground.add_child(chunk)
				chunk.owner = ground
		var scene := PackedScene.new()
		scene.pack(ground)
		ground.free()
		var err := ResourceSaver.save(scene, "%s/world-%d.scn" % [OUTPUT, seed_id], ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("Could not save compiled terrain %d (%d)" % [seed_id, err])
			quit(1)
			return
	quit()

func _compile_detail(seed_id: int) -> bool:
	var cells: Array[Vector2i] = []
	for runway in [false, true]:
		var position := BATTLE.start_position("free", {}, runway)
		for cell in WORLD.opening_tiles(position):
			cells.append(cell)
		# Include the first forward band reached after the opening tiles.
		for x in range(-2, 3):
			cells.append(Vector2i(floori(position.x / WORLD.TILE) + x, floori(position.z / WORLD.TILE) - 3))
	var payloads: Array[PackedByteArray] = []
	for cell in cells:
		var encoded := _encode_tile(WORLD.bake_tile(cell, seed_id))
		if encoded.is_empty():
			return false
		payloads.append(encoded.compress(FileAccess.COMPRESSION_ZSTD))
	var file := FileAccess.open("%s/detail-%d.terrainpack" % [OUTPUT, seed_id], FileAccess.WRITE)
	if not file:
		return false
	file.store_32(WORLD.FINE_PACK_MAGIC)
	file.store_16(WORLD.SIZE)
	file.store_16(int(WORLD.STEP))
	file.store_32(cells.size())
	for i in cells.size():
		file.store_32(cells[i].x)
		file.store_32(cells[i].y)
		file.store_32(payloads[i].size())
	for data in payloads:
		file.store_buffer(data)
	print("Compiled ", cells.size(), " fine regions for ", seed_id, " (", file.get_position(), " bytes)")
	return file.get_error() == OK

func _encode_tile(heights: PackedFloat32Array) -> PackedByteArray:
	var encoded := PackedByteArray()
	encoded.resize(WORLD.FINE_TILE_BYTES)
	var first := roundi(heights[0] * 16.0)
	encoded.encode_s32(0, first)
	var previous := PackedInt32Array()
	previous.resize(WORLD.SIZE)
	for y in WORLD.SIZE:
		var west := 0
		var northwest := 0
		for x in WORLD.SIZE:
			var i := y * WORLD.SIZE + x
			var north := previous[x]
			var height := roundi(heights[i] * 16.0)
			var delta := height - (first if i == 0 else west + north - northwest)
			if delta < -32768 or delta > 32767:
				return PackedByteArray()
			encoded.encode_s16(4 + i * 2, delta)
			previous[x] = height
			west = height
			northwest = north
	return encoded

func _patch(heights: PackedFloat32Array, origin: Vector2, x0: int, z0: int, snow: bool, storm: bool) -> ArrayMesh:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var faces := PackedInt32Array()
	var sun := Vector3(-0.74, 0.59, 0.33) if snow else (Vector3(0.50, 0.218, -0.84) if storm else Vector3(-0.88, 0.31, -0.36))
	var rock := Color(0.17, 0.187, 0.205) if snow else (Color(0.102, 0.115, 0.115) if storm else Color(0.145, 0.161, 0.157))
	for z in range(z0, z0 + PATCH + 1):
		for x in range(x0, x0 + PATCH + 1):
			var i := z * EDGE + x
			var y := heights[i]
			points.append(Vector3(origin.x + SPACING * x, y, origin.y + SPACING * z))
			var dx := (heights[z * EDGE + mini(EDGE - 1, x + 1)] - heights[z * EDGE + maxi(0, x - 1)]) / (2.0 * SPACING)
			var dz := (heights[mini(EDGE - 1, z + 1) * EDGE + x] - heights[maxi(0, z - 1) * EDGE + x]) / (2.0 * SPACING)
			var normal := Vector3(-dx, 1, -dz).normalized()
			var powder := smoothstep(220.0, 630.0, y) * smoothstep(0.73, 0.97, normal.y) if snow else 0.0
			var base := rock.lerp(Color(0.50, 0.57, 0.63), powder)
			colors.append(base * (0.59 + clampf(normal.dot(sun), 0.0, 1.0) * 0.52))
			if x < x0 + PATCH and z < z0 + PATCH:
				var index := (z - z0) * (PATCH + 1) + x - x0
				# Ocean is opaque. Fully submerged triangles cannot contribute to the horizon.
				var next := heights[i + 1]
				var below := heights[i + EDGE]
				if maxf(y, maxf(next, below)) > -4.0:
					faces.append_array(PackedInt32Array([index, index + PATCH + 1, index + 1]))
				if maxf(heights[i + EDGE + 1], maxf(next, below)) > -4.0:
					faces.append_array(PackedInt32Array([index + 1, index + PATCH + 1, index + PATCH + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = faces
	var resource := ArrayMesh.new()
	if not faces.is_empty():
		resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return resource
