extends SceneTree

const WORLD = preload("res://game/world.gd")
const DATA = preload("res://game/catalogue.gd")
const BATTLE = preload("res://game/battle.gd")
const SPACING := 192.0
const EDGE := int(WORLD.RESIDENT_SIDE * WORLD.TILE / SPACING) + 1
const PATCH := 96
const OUTPUT := "res://assets/environment"

func _initialize() -> void:
	call_deferred("compile")

func compile() -> void:
	for theatre in DATA.new().source.theatres:
		var seed_id := int(theatre.seed)
		if "--frost-only" in OS.get_cmdline_user_args() and seed_id != 704:
			continue
		WORLD.prepare_relief(seed_id)
		if not "--coverage-only" in OS.get_cmdline_user_args() and not _compile_detail(seed_id):
			push_error("Could not save fine terrain for %d" % seed_id)
			quit(1)
			return
		if "--detail-only" in OS.get_cmdline_user_args():
			continue
		var origin := Vector2(WORLD.RESIDENT_MIN) * WORLD.TILE
		var heights: PackedFloat32Array = ClassDB.class_call_static("SkyTerrainKernel", "height_tile",
			origin.x, origin.y, EDGE, SPACING, seed_id)
		var climate := WORLD.snow_controls(origin, EDGE, SPACING, heights) if bool(theatre.snow) else PackedByteArray()
		var ground := Node3D.new()
		var geology: Image
		if WORLD.FIELDS.has(seed_id):
			var source := "%s/%s-color.png" % [OUTPUT, WORLD.FIELDS[seed_id]]
			geology = (load(source) as Texture2D).get_image()
		for z in range(0, EDGE - 1, PATCH):
			for x in range(0, EDGE - 1, PATCH):
				var chunk := MeshInstance3D.new()
				var inner := x in [PATCH, PATCH * 2] and z in [PATCH, PATCH * 2]
				chunk.mesh = _patch(heights, origin, Vector2i(x, z), 1 if inner else 2, theatre, geology, climate)
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

func _patch(heights: PackedFloat32Array, origin: Vector2, start: Vector2i, stride: int, theatre: Dictionary, geology: Image, climate: PackedByteArray) -> ArrayMesh:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var snow: bool = theatre.snow
	var storm: bool = int(theatre.seed) == 116
	var row_size := PATCH / stride + 1
	var sun := Vector3(-0.74, 0.59, 0.33) if snow else (Vector3(0.50, 0.218, -0.84) if storm else Vector3(-0.88, 0.31, -0.36))
	var rock := Color(0.18, 0.16, 0.143) if snow else (Color(0.102, 0.115, 0.115) if storm else Color(0.145, 0.161, 0.157))
	for z in range(start.y, start.y + PATCH + 1, stride):
		for x in range(start.x, start.x + PATCH + 1, stride):
			var i := z * EDGE + x
			var y := heights[i]
			# Odd edge vertices lie on the matching coarse segments.
			if stride == 1:
				if (x == start.x or x == start.x + PATCH) and z % 2 == 1:
					y = (heights[i - EDGE] + heights[i + EDGE]) * 0.5
				elif (z == start.y or z == start.y + PATCH) and x % 2 == 1:
					y = (heights[i - 1] + heights[i + 1]) * 0.5
			var at := origin + Vector2(x, z) * SPACING
			points.append(Vector3(at.x, y, at.y))
			var dx := (heights[z * EDGE + mini(EDGE - 1, x + 1)] - heights[z * EDGE + maxi(0, x - 1)]) / (2.0 * SPACING)
			var dz := (heights[mini(EDGE - 1, z + 1) * EDGE + x] - heights[maxi(0, z - 1) * EDGE + x]) / (2.0 * SPACING)
			var normal := Vector3(-dx, 1, -dz).normalized()
			var powder := float((climate.decode_u32(i * 4) >> 14) & 255) / 255.0 if snow else 0.0
			var base := rock.lerp(Color(0.56, 0.63, 0.70), powder)
			if geology:
				var field_origin := Vector2(6144, 6144) if snow else Vector2(6250, 6200)
				var cell := Vector2i(((at + field_origin) / 24.0).round())
				if Rect2i(Vector2i.ZERO, geology.get_size()).has_point(cell):
					var tint := geology.get_pixelv(cell).srgb_to_linear()
					base *= Color.WHITE.lerp(tint, 0.48)
			colors.append(base * (0.59 + clampf(normal.dot(sun), 0.0, 1.0) * 0.52))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var faces := _faces(points, row_size, 1)
	arrays[Mesh.ARRAY_INDEX] = faces
	var resource := ArrayMesh.new()
	if not faces.is_empty():
		var lods := {}
		if stride == 1:
			var coarse_faces := _faces(points, row_size, 2)
			if not coarse_faces.is_empty():
				lods[_vertical_error(points, row_size)] = coarse_faces
		resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return resource

func _faces(points: PackedVector3Array, row_size: int, stride: int) -> PackedInt32Array:
	var faces := PackedInt32Array()
	var row_stride := row_size * stride
	for z in range(0, row_size - 1, stride):
		for x in range(0, row_size - 1, stride):
			var index := z * row_size + x
			# Ocean is opaque. Fully submerged triangles cannot contribute to the horizon.
			var next := points[index + stride].y
			var below := points[index + row_stride].y
			if maxf(points[index].y, maxf(next, below)) > -4.0:
				faces.append_array(PackedInt32Array([index, index + row_stride, index + stride]))
			if maxf(points[index + row_stride + stride].y, maxf(next, below)) > -4.0:
				faces.append_array(PackedInt32Array([index + stride, index + row_stride, index + row_stride + stride]))
	return faces

func _vertical_error(points: PackedVector3Array, side: int) -> float:
	var error := 0.5
	for z in side:
		for x in side:
			if x % 2 == 0 and z % 2 == 0:
				continue
			var i := z * side + x
			var offset := 1 if z % 2 == 0 else (side if x % 2 == 0 else side - 1)
			var coarse := (points[i - offset].y + points[i + offset].y) * 0.5
			error = maxf(error, absf(points[i].y - coarse))
	return error
