extends RefCounted

const NAMES := {"a10": "雷电二型", "alphajet": "阿尔法喷气", "b2": "幽灵轰炸机", "bf109": "梅塞施密特战斗机", "c130": "大力神运输机", "camel": "索普威斯骆驼", "dr1": "福克三翼机", "e2": "鹰眼预警机", "ea6b": "徘徊者电子战机", "f16": "战隼战斗机", "g91": "菲亚特攻击机", "gripen": "鹰狮战斗机", "hornet": "大黄蜂战斗机", "j10": "歼十战斗机", "j20": "歼二十战斗机", "me262": "燕式喷气战斗机", "mig21": "米格二十一战斗机", "mirage": "幻影两千战斗机", "p51": "野马战斗机", "shade-drone": "影隼无人机", "spitfire": "喷火战斗机", "su35": "苏三十五战斗机", "zero": "零式战斗机"}

const MISSILES = {
	"interceptor": {"label":"巡星标准弹", "price":0, "acquire":0.69, "range":4950.0, "turn":2.23, "speed":1040.0, "accel":490.0, "life":8.0, "damage":118.0},
	"flarewing": {"label":"赤尾红外弹", "price":620, "acquire":0.43, "range":3870.0, "turn":3.36, "speed":940.0, "accel":545.0, "life":6.5, "damage":112.0},
	"skylance": {"label":"苍矛远程弹", "price":1150, "acquire":0.91, "range":6100.0, "turn":1.82, "speed":1340.0, "accel":635.0, "life":9.5, "damage":144.0},
}
const TRAINING = [
	["基础飞行", "滑动控制方向，保持安全飞行十五秒。", "flight"],
	["航炮瞄准", "使用航炮命中练习机。", "gun"],
	["锁定与发射", "自动捕捉目标，发射导弹并命中。", "missile"],
	["来袭反制", "使用反制导弹解除来袭威胁。", "counter"],
	["规避机动", "在敌弹接近时执行规避。", "evade"],
]
const UPGRADE_LABELS = {"weapons":"航炮威力", "warhead":"导弹威力", "engine":"发动机推力", "maneuver":"舵面响应", "armor":"复合装甲", "radar":"数字雷达"}
const UPGRADE_GAINS = {"weapons":0.07, "warhead":0.12, "engine":0.06, "maneuver":0.06, "armor":0.065, "radar":150.0}
const AIRCRAFT_PRICE := 1150
const UPGRADE_LIMIT := 3
const RADAR_DISPLAY_GAIN := 350.0
const UNLOCK_LEVELS = {"mirage":4, "hornet":6, "gripen":7, "su35":10}

var source: Dictionary
var planes := {}
var scenes := {}

func _init() -> void:
	source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/campaign.json"))
	for plane in source.fleet:
		plane.name = NAMES.get(plane.id, "战机")
		planes[plane.id] = plane

func aircraft(id: String) -> Dictionary:
	return planes.get(id, planes.j20)

static func upgrade_price(level_now: int) -> int:
	return 560 + level_now * 360

static func mesh_path(id: String) -> String:
	return "res://assets/fleet/%s.glb" % id

func mesh(id: String) -> Node3D:
	if not scenes.has(id):
		scenes[id] = load(mesh_path(id))
	var tree: Node3D = scenes[id].instantiate()
	for child in tree.get_children():
		if child is Node3D:
			child.visible = child.name == "Exterior"
	return tree

func gear_tracks(model: Node3D) -> Array[Dictionary]:
	var tracks: Array[Dictionary] = []
	for player in model.find_children("*", "AnimationPlayer", true, false):
		for name in player.get_animation_list():
			if not String(name).begins_with("Gear_"):
				continue
			var clip: Animation = player.get_animation(name)
			var track_root: Node = player.get_node(player.root_node)
			for index in clip.get_track_count():
				if clip.track_get_type(index) != Animation.TYPE_ROTATION_3D:
					continue
				var path := clip.track_get_path(index)
				var hinge := track_root.get_node_or_null(NodePath(path.get_concatenated_names())) as Node3D
				var count := clip.track_get_key_count(index)
				if hinge and hinge.name == name and count > 1:
					tracks.append({"hinge":hinge, "stowed":clip.track_get_key_value(index, 0),
						"deployed":clip.track_get_key_value(index, count - 1)})
					break
	return tracks

func set_gear(tracks: Array, extension: float) -> void:
	for track in tracks:
		track.hinge.quaternion = track.stowed.slerp(track.deployed, extension).normalized()

func missile_compatible(plane: Dictionary, weapon_id: String) -> bool:
	return not plane.support and not plane.rails.is_empty() and (weapon_id != "skylance" or plane.era in ["modern", "stealth"])

static func level(xp: int) -> int:
	return floori((sqrt(44100.0 + 96.0 * (maxi(0, xp) + 0.5)) - 210.0) / 48.0) + 1
