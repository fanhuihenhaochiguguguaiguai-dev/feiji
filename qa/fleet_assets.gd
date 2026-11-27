extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")
const Trails = preload("res://game/volumetric_trails.gd")

var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var data := Data.new()
	var battle := Battle.new()
	root.add_child(battle)
	battle.setup(data, Profile.new(data), "training", {"name":"机队资源", "region":0, "lesson":"flight"}, false)
	battle.set_physics_process(false)
	battle.set_process(false)
	var jet := battle.fleet[1]
	var checked := 0
	for spec: Dictionary in data.source.fleet:
		var id: String = spec.id
		battle._change_plane(jet, id)
		check(exterior_ready(jet.rig.levels), id + " three detail levels")
		check(jet.rig.gear.size() == (0 if spec.gearFixed else 3), id + " landing gear tracks")
		data.set_gear(jet.rig.gear, 1.0)
		for track in jet.rig.gear:
			check(track.hinge.quaternion.angle_to(track.deployed) < 0.001, id + " landing gear pose")
		check(jet.rig.exhausts.size() == (spec.engine.size() if spec.props.is_empty() else 0), id + " engine mounts")
		if id != "j20":
			for i in jet.rig.exhausts.size():
				var p: Array = spec.engine[i]
				check(jet.rig.exhausts[i].position.is_equal_approx(Vector3(p[0], p[1], p[2])), id + " engine frame")
		var proxies: Array[Transform3D] = jet.rig.hit_proxies
		var wreck: Node3D = jet.rig.breakup
		check(wreck != null and wreck.get_child_count() == 5, id + " pre-fractured parts")
		if wreck:
			for piece: Node in wreck.get_children():
				check(piece is MeshInstance3D and piece.mesh != null and piece.mesh.get_surface_count() > 0, id + " wreck geometry")
		check(not proxies.is_empty() and proxies.size() <= 25, id + " collision sections")
		if not proxies.is_empty():
			var bounds: AABB = jet.rig.hit_bounds
			var center := proxies[0].affine_inverse().origin
			var traverse := Vector3.UP * (bounds.size.y + 2.0)
			var hit := Battle._trace_airframe(jet, center + traverse, center - traverse, INF)
			var offset := Vector3(bounds.end.x - center.x + 2.0, 0.0, 0.0)
			var miss := Battle._trace_airframe(jet, center + offset + traverse, center + offset - traverse, INF)
			check(hit.x >= 0.0 and hit.x < 0.52 and is_inf(miss.x), id + " continuous hit and miss")
		checked += 1
	check(checked == 23, "fleet count")

	var missile_plume := battle.effects.jet_plume(Vector3.ONE, true)
	var aircraft_plume := battle.effects.jet_plume(Vector3.ONE, false)
	check(is_equal_approx(missile_plume.material_override.get_shader_parameter("intensity"), 5.993), "missile emission")
	check(is_equal_approx(aircraft_plume.material_override.get_shader_parameter("intensity"), 2.65), "aircraft emission")
	missile_plume.free()
	aircraft_plume.free()
	var trails := Trails.new()
	root.add_child(trails)
	trails.setup(null, Color.WHITE, Vector3.UP)
	for style in Trails.Style.values():
		trails.extend(style, Vector3.ZERO, style, 1.0)
		trails.close(style)
	trails.advance(1.48)
	check(trails.free_slots.size() == Trails.SLOTS - 2, "missile smoke still present at 1.48 s")
	trails.advance(0.06)
	check(trails.free_slots.size() == Trails.SLOTS - 1, "only missile smoke expires at 1.5 s")
	check(Trails.LIFETIME == [1.50, 2.65, 0.92], "wake lifetimes")
	trails.queue_free()
	battle.queue_free()
	await process_frame
	print(JSON.stringify({"aircraft":checked, "failures":failures}))
	quit(int(not failures.is_empty()))


func exterior_ready(levels: Dictionary) -> bool:
	for level: Node3D in levels.values():
		if not level or level.find_children("*", "MeshInstance3D", true, false).is_empty():
			return false
	return true


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
