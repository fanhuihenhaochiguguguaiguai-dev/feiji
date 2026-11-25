extends RefCounted
## Adapted from Aircraft.update_IA, update_autopilot and update_target_lock
## in HARFANG Dogfight Sandbox HG1, source/Machines.py, 508b2cdda.
## Copyright (c) 2018 Movida Production. MIT license alongside this file.

const Airframe = preload("res://game/flight_body.gd")
const START_GUN := cos(deg_to_rad(9.0))
const START_LOCK := cos(deg_to_rad(21.0))
const HOLD_LOCK := cos(deg_to_rad(26.0))

static func steer(jet: Airframe, course: Vector3, destination_altitude: float) -> Vector3:
	var heading := Vector3(jet.forward.x, 0.0, jet.forward.z).normalized()
	var direction := Vector3(course.x, 0.0, course.z).normalized()
	var heading_error := atan2(-heading.cross(direction).y, heading.dot(direction))
	var bank_goal := -signf(heading_error) * pow(clampf(absf(heading_error) / (PI * 0.5), 0.0, 1.0), 0.5) * 0.67
	var bank := atan2((jet.attitude * Vector3.RIGHT).y, (jet.attitude * Vector3.UP).y)
	var height_error := destination_altitude - jet.position.y
	var pitch_goal := signf(height_error) * pow(clampf(absf(height_error) / 410.0, 0.0, 1.0), 0.7) * 0.33
	var pitch := asin(clampf(jet.forward.y, -1.0, 1.0))
	var yaw := clampf(heading_error * 1.24, -0.91, 0.91)
	return Vector3(clampf((pitch_goal - pitch) * 2.65, -0.49, 0.61), yaw, clampf((bank_goal - bank) * 1.54, -0.62, 0.62))

static func target_for(jet: Airframe, fleet: Array[Airframe]) -> Airframe:
	var nearest := INF
	var choice: Airframe
	for candidate in fleet:
		if candidate.side == jet.side or candidate.hp <= 0.0:
			continue
		var distance := candidate.position.distance_squared_to(jet.position)
		if candidate == jet.target:
			distance *= 0.68
		if distance < nearest:
			nearest = distance
			choice = candidate
	return choice

static func command(jet: Airframe, fleet: Array[Airframe], landscape: Node3D, time: float, dt: float) -> Dictionary:
	if not jet.target or jet.target.hp <= 0.0 or time >= jet.ai_until:
		var next := target_for(jet, fleet)
		if next != jet.target:
			jet.ai_lock = 0.0
		jet.target = next
		jet.ai_until = time + 0.75 + 0.045 * float(jet.index % 5)
	var enemy: Airframe = jet.target
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
		altitude = enemy.position.y - minf(25.0, distance * 0.021) + float(jet.index % 3) * 10.0
		if distance < 155.0 and alignment < 0.18:
			# Briefly open separation when the opponent crosses the nose.
			course = jet.forward * 430.0 + course * 0.18
			altitude += 50.0
		if distance > 2800.0:
			throttle = 0.91
		elif distance < 650.0:
			throttle = 0.61
		jet.ai_state = "attack" if distance < 1600.0 else "intercept"
		cannon = time >= jet.shot_at and distance < 1020.0 and alignment > START_GUN
		if distance > 420.0 and distance < 2500.0 and alignment > START_LOCK:
			jet.ai_lock = minf(0.86, jet.ai_lock + dt)
		else:
			jet.ai_lock = maxf(0.0, jet.ai_lock - dt * 1.8)
		missile = not jet.type.rails.is_empty() and time >= jet.missile_at and distance > 400.0 and distance < 2500.0 and alignment > HOLD_LOCK and jet.ai_lock >= lerpf(0.48, 0.78, distance / 2500.0)
		if missile and landscape.obstruction(jet.position, enemy.position):
			missile = false
	var projected := jet.position + jet.forward * maxf(225.0, jet.velocity.length() * 1.75)
	var safety: float = maxf(landscape.height(projected), landscape.height(jet.position)) + 105.0
	if projected.y < safety:
		jet.ai_safe_altitude = maxf(jet.ai_safe_altitude, safety + 36.0)
	elif jet.position.y >= jet.ai_safe_altitude - 12.0:
		jet.ai_safe_altitude = -INF
	if jet.ai_safe_altitude > altitude:
		altitude = jet.ai_safe_altitude
		throttle = maxf(0.83, throttle)
		jet.ai_state = "terrain"
		missile = false
	var control := steer(jet, course, altitude)
	if time < jet.evade_until:
		jet.ai_state = "evade"
		control += Vector3(0.21, jet.evade_side * 0.46, -jet.evade_side * 0.35)
		missile = false
	return {"control":control, "throttle":throttle, "gun":cannon, "missile":missile}
