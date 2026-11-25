extends RefCounted
## Adapted from Aircraft.update_IA, update_autopilot and update_target_lock
## in HARFANG Dogfight Sandbox HG1, source/Machines.py, 508b2cdda.
## Copyright (c) 2018 Movida Production. MIT license alongside this file.

const Airframe = preload("res://game/flight_body.gd")
const START_GUN := cos(deg_to_rad(9.0))
const START_LOCK := cos(deg_to_rad(21.0))
const HOLD_LOCK := cos(deg_to_rad(26.0))
const MAX_PURSUERS := 2

static func steer(jet: Airframe, course: Vector3, destination_altitude: float) -> Vector3:
	var heading := Vector3(jet.forward.x, 0.0, jet.forward.z).normalized()
	var direction := Vector3(course.x, 0.0, course.z).normalized()
	var heading_error := atan2(-heading.cross(direction).y, heading.dot(direction))
	var height_error := destination_altitude - jet.position.y
	var pitch_goal := signf(height_error) * pow(clampf(absf(height_error) / 410.0, 0.0, 1.0), 0.7) * 0.33
	var pitch := asin(clampf(jet.forward.y, -1.0, 1.0))
	var yaw := clampf(heading_error * 1.24, -0.91, 0.91)
	return Vector3(clampf((pitch_goal - pitch) * 2.65, -0.49, 0.61), yaw, 0.0)

static func assign(fleet: Array[Airframe], rotation: int) -> void:
	var pursuits := PackedInt32Array()
	pursuits.resize(fleet.size())
	var bots := fleet.size() - 1
	for step in bots:
		var jet := fleet[1 + (rotation + step) % bots]
		var choice: Airframe
		var best := INF
		if jet.hp > 0.0:
			for other in fleet:
				if other.side == jet.side or other.hp <= 0.0 or pursuits[other.index] >= MAX_PURSUERS:
					continue
				var delta := other.position - jet.position
				var bearing := jet.forward.dot(delta.normalized())
				var cost := delta.length() + (1.0 - bearing) * 620.0 + pursuits[other.index] * 580.0
				if other == jet.target:
					cost -= 360.0
				if cost < best:
					choice = other
					best = cost
		if choice:
			pursuits[choice.index] += 1
		if choice != jet.target:
			jet.ai_lock = 0.0
		jet.target = choice

static func command(jet: Airframe, fleet: Array[Airframe], engagement_centre: Vector3, landscape: Node3D, ground: float, time: float, dt: float) -> Dictionary:
	var enemy: Airframe = jet.target if jet.target and jet.target.hp > 0.0 else null
	var course := jet.forward
	var altitude := jet.position.y
	var throttle := 0.70
	var cannon := false
	var missile := false
	if enemy:
		var delta := enemy.position - jet.position
		var distance := delta.length()
		var alignment := jet.forward.dot(delta.normalized())
		course = delta + (enemy.velocity - jet.velocity * 0.45) * clampf(distance / 1450.0, 0.12, 1.15)
		altitude = enemy.position.y + lerpf(float(jet.index % 5 - 2) * 64.0, 0.0, 1.0 - smoothstep(430.0, 1600.0, distance))
		if distance < 190.0 and alignment < 0.18:
			# Briefly open separation when the opponent crosses the nose.
			course = jet.forward * 540.0 + course * 0.14
			altitude += 24.0 if jet.index % 2 == 0 else -24.0
		if distance > 2800.0:
			throttle = 0.91
		elif distance < 650.0:
			throttle = 0.61
		var gun_point := delta + (enemy.velocity - jet.velocity * 0.60) * (distance / float(jet.type.cannon[1]))
		cannon = time >= jet.shot_at and distance < 1050.0 and jet.forward.dot(gun_point.normalized()) > START_GUN
		if distance > 420.0 and distance < 2500.0 and alignment > START_LOCK:
			jet.ai_lock = minf(0.86, jet.ai_lock + dt)
		else:
			jet.ai_lock = maxf(0.0, jet.ai_lock - dt * 1.8)
		missile = not jet.type.rails.is_empty() and time >= jet.missile_at and distance > 400.0 and distance < 2500.0 and alignment > HOLD_LOCK and jet.ai_lock >= lerpf(0.48, 0.78, distance / 2500.0)
		if missile and landscape.obstruction(jet.position, enemy.position):
			missile = false
	else:
		# Other wingmen approach separated points until one of the attack slots is free.
		var offset := Vector3.FORWARD.rotated(Vector3.UP, jet.index * 2.39996 + time * 0.14) * (860.0 + jet.index * 74.0)
		course = engagement_centre + offset - jet.position
		altitude = engagement_centre.y + 100.0 + float(jet.index % 4) * 72.0
	if time >= jet.ai_safety_at:
		jet.ai_safety_at = time + 0.14 + (jet.index % 4) * 0.013
		jet.ai_avoidance = separation(jet, fleet)
		var projected := jet.position + jet.forward * maxf(345.0, jet.velocity.length() * 2.9)
		var safety: float = maxf(landscape.height(projected), ground) + 130.0
		jet.ai_safe_altitude = safety + 40.0 if projected.y < safety else -INF
	course = course.normalized() + jet.ai_avoidance * Vector3(0.62, 0, 0.62)
	altitude += jet.ai_avoidance.y * 135.0
	if jet.ai_safe_altitude > altitude:
		altitude = jet.ai_safe_altitude
		throttle = maxf(0.83, throttle)
		missile = false
	var control := steer(jet, course, altitude)
	if time < jet.evade_until:
		control += Vector3(0.21, jet.evade_side * 0.46, -jet.evade_side * 0.35)
		missile = false
	return {"control":control, "throttle":throttle, "gun":cannon, "missile":missile}

static func separation(jet: Airframe, fleet: Array[Airframe]) -> Vector3:
	var correction := Vector3.ZERO
	for other in fleet:
		if other == jet or other.hp <= 0.0:
			continue
		var away := (jet.position - other.position) + (jet.velocity - other.velocity) * 0.34
		var distance := away.length()
		if distance < 360.0:
			var strength := 1.0 - distance / 360.0
			correction += away.normalized() * strength
			correction.y += strength * (0.45 if jet.index > other.index else -0.45)
	return correction.limit_length()
