extends RefCounted

const MISSILES = {
	"interceptor": {"label":"巡星标准弹", "price":0, "acquire":0.69, "range":4950.0, "turn":2.23, "speed":1040.0, "accel":490.0, "life":8.0, "damage":118.0, "infrared":false},
	"flarewing": {"label":"赤尾红外弹", "price":620, "acquire":0.43, "range":3870.0, "turn":3.36, "speed":940.0, "accel":545.0, "life":6.5, "damage":112.0, "infrared":true},
	"skylance": {"label":"苍矛远程弹", "price":1150, "acquire":0.91, "range":6100.0, "turn":1.82, "speed":1340.0, "accel":635.0, "life":9.5, "damage":144.0, "infrared":false},
}
const TRAINING = [
	["基础飞行", "保持飞行并调整油门。", "flight"],
	["航炮瞄准", "使用航炮命中练习机。", "gun"],
	["锁定与发射", "自动捕捉目标，发射导弹并命中。", "missile"],
	["来袭反制", "使用反制导弹解除来袭威胁。", "counter"],
	["规避机动", "在敌弹接近时执行规避。", "evade"],
]
const UPGRADE_LABELS = {"weapons":"航炮威力", "warhead":"导弹威力", "engine":"发动机推力", "maneuver":"舵面响应", "armor":"复合装甲", "radar":"数字雷达"}
const UPGRADE_GAINS = {"weapons":0.07, "warhead":0.12, "engine":0.06, "maneuver":0.06, "armor":0.065, "radar":150.0}
const UNLOCK_LEVELS = {"mirage":4, "hornet":6, "gripen":7, "su35":10}

var source: Dictionary
var planes := {}
var scenes := {}

func _init() -> void:
	source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campaign.json"))
	for plane in source.fleet:
		planes[plane.id] = plane

func aircraft(id: String) -> Dictionary:
	return planes.get(id, planes.j20)

func mesh(id: String) -> Node3D:
	if not scenes.has(id):
		scenes[id] = load("res://assets/fleet/%s.glb" % id)
	var tree: Node3D = scenes[id].instantiate()
	for child in tree.get_children():
		if child is Node3D:
			child.visible = child.name == "Exterior"
	return tree

func missile_compatible(plane: Dictionary, weapon_id: String) -> bool:
	return not plane.support and not plane.rails.is_empty() and (weapon_id != "skylance" or plane.era in ["modern", "stealth"])

static func level(xp: int) -> int:
	return floori((sqrt(44100.0 + 96.0 * (maxi(0, xp) + 0.5)) - 210.0) / 48.0) + 1
