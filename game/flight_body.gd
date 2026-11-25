extends RefCounted

# Angle of attack runs from -40 to +40 degrees at five-degree spacing.
const LIFT_CURVE := [-0.40, -0.29, -0.16, 0.09, 0.28, 0.47, 0.66, 0.86, 1.04, 1.19, 1.34, 1.46, 1.52, 1.34, 1.05, 0.77, 0.51]
const DRAG_CURVE := [9.2, 7.1, 5.2, 3.65, 2.32, 1.30, 0.58, 0.15, 0.0, 0.15, 0.58, 1.3, 2.32, 3.65, 5.2, 7.1, 9.2]

var type: Dictionary
var position := Vector3.ZERO
var previous := Vector3.ZERO
var velocity := Vector3.ZERO
var angular := Vector3.ZERO
var attitude := Quaternion.IDENTITY
var forward := Vector3.FORWARD
var hp := 0.0
var max_hp := 0.0
var throttle := 0.74
var boost := 0.0
var gear := 0.0
var gear_target := 0.0
var grounded := false
var aoa := 0.0
var stall := 0.0
var load_g := 1.0
var engine := 1.0
var handling := 1.0
var damage := Vector3.ZERO
var side := 0
var index := 0
var kills := 0
var deaths := 0
var life_id := 0
var model: Node3D
var rig := {}
var until_respawn := 0.0
var shot_at := 0.0
var missile_at := 0.0
var evade_until := 0.0
var evade_at := 0.0
var evade_side := 1.0
var counter_at := 0.0
var counter_until := 0.0
var counter_age := 0.0
var ai_state := "intercept"
var ai_until := 0.0
var target: RefCounted

func reset(at: Vector3, nose: Vector3, initial_speed: float, health: float, runway := false) -> void:
	life_id += 1
	until_respawn = 0.0
	position = at
	previous = at
	forward = nose.normalized()
	attitude = Basis.looking_at(forward, Vector3.UP).get_rotation_quaternion()
	velocity = forward * initial_speed
	angular = Vector3.ZERO
	damage = Vector3.ZERO
	hp = health
	max_hp = health
	throttle = 0.74
	boost = 0.0
	aoa = 0.0
	stall = 0.0
	gear = 1.0 if runway or type.gearFixed else 0.0
	gear_target = gear
	grounded = runway
	shot_at = 0.0
	missile_at = 0.0
	evade_until = 0.0
	evade_at = 0.0
	counter_at = 0.0
	counter_until = 0.0
	ai_until = 0.0
	ai_state = "intercept"
	target = null

func move(dt: float, command: Vector3, engine_command: float, afterburner: bool, ground: float, runway: bool) -> void:
	var speed := velocity.length()
	var up := attitude * Vector3.UP
	var right := attitude * Vector3.RIGHT
	var slope := asin(clampf(forward.y, -1.0, 1.0))
	var bank := atan2(right.y, up.y)
	var input := command.limit_length(1.4)
	var control := clampf((speed - type.stall * 0.35) / (type.stall * 0.9), 0.21, 1.0)
	control *= clampf(1.0 - (speed / type.maxSpeed - 0.63) * 0.66, 0.62, 1.0)
	var correction := Vector3.ZERO
	if up.y > 0.18:
		correction.x = clampf(-slope * 0.98 - velocity.y / (type.trim * 10.0), -0.52, 0.52) * (1.0 - clampf(absf(input.x) * 7.0, 0.0, 1.0))
		correction.z = clampf((input.y * 1.02 - bank) * 3.26, -2.46, 2.46) * (1.0 - clampf(absf(input.z) * 6.0, 0.0, 1.0))
		correction.y = right.y * 0.40
	var nose_rate: float = input.x * type.pitch * (0.72 + 0.63 * sqrt(absf(input.x)))
	if input.x > 0.0 and up.y > 0.0:
		nose_rate = minf(nose_rate, (1.29 - slope) * 3.7)
	nose_rate *= 1.0 - 0.52 * stall
	var target_rate := Vector3(nose_rate, -input.y * type.yaw * (1.0 + absf(input.y) * 0.65), input.z * type.roll)
	target_rate *= control * type.grip * handling * lerpf(0.78, 1.0, hp / max_hp)
	target_rate += correction + Vector3(0.0, 0.0, (damage.y - damage.x) * 0.46)
	angular = angular.lerp(target_rate, 1.0 - exp(-dt * 8.65 / clampf(0.82 + type.span * type.length / 1150.0, 0.86, 1.64)))
	if grounded:
		angular *= Vector3(1.0, 0.82, 0.35)
		angular.x = clampf(angular.x, -0.015, 0.7)
	if angular.length_squared() > 0.000001:
		attitude = (attitude * Quaternion(angular.normalized(), angular.length() * dt)).normalized()
	forward = attitude * Vector3.FORWARD
	up = attitude * Vector3.UP
	right = attitude * Vector3.RIGHT
	throttle = lerpf(throttle, engine_command, 1.0 - exp(-dt * 3.1))
	boost = lerpf(boost, float(afterburner and type.boost > 0.0), 1.0 - exp(-dt * 5.1))
	gear = lerpf(gear, gear_target, 1.0 - exp(-dt * 2.65))
	var density := clampf(1.0 - position.y / 18500.0, 0.62, 1.08)
	var down_speed := velocity.dot(up)
	var cross := velocity.dot(right)
	aoa = atan2(-down_speed, maxf(type.stall * 0.5, velocity.dot(forward)))
	stall = clampf((type.stall - speed) / (type.stall * 0.45) + maxf(0.0, absf(aoa) - 0.39) * 1.7, 0.0, 1.0)
	var slot := clampf(rad_to_deg(aoa) / 5.0 + 8.0, 0.0, 15.999)
	var index_lut := floori(slot)
	var cl := lerpf(LIFT_CURVE[index_lut], LIFT_CURVE[index_lut + 1], slot - index_lut)
	var cd := lerpf(DRAG_CURVE[index_lut], DRAG_CURVE[index_lut + 1], slot - index_lut)
	var lift_factor := clampf((speed / type.stall - 0.50) * 1.76, 0.015, 1.0)
	var max_load := 3.0 if type.support else (4.48 if not type.props.is_empty() else 5.92)
	load_g = clampf(cl * pow(speed / type.trim, 2.0) * lift_factor * density, -1.17, max_load)
	var nominal: float = 12.0 + type.trim * 0.128
	var thrust: float = (3.0 + nominal * throttle + type.boost * boost) * density * engine * type.acceleration * (1.0 - damage.z * 0.35) * lerpf(0.7, 1.0, hp / max_hp)
	var drag: float = (3.0 + nominal + type.boost) * density * pow(speed / type.maxSpeed, 2.0)
	drag += speed * gear * 0.010 + (cd + absf(cross) * 0.014) * clampf(speed / type.trim, 0.25, 1.7) + (absf(angular.x) + absf(angular.y)) * 2.02
	var acceleration := forward * thrust - velocity.normalized() * drag - Vector3.UP * 9.81
	acceleration += up * (load_g * 9.81 - down_speed * lift_factor * 2.25) - right * cross * 2.78
	previous = position
	velocity += acceleration * dt
	position += velocity * dt
	if grounded:
		if runway and not (forward.y > 0.098 and speed > type.stall * 1.20 and command.x > 0.21):
			position.y = ground + maxf(0.8, type.gearClearance)
			velocity.y = 0.0
			velocity *= exp(-dt * (0.39 if throttle < 0.28 else 0.041))
		else:
			grounded = false
			velocity.y = maxf(velocity.y, 9.0)
