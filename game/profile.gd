extends RefCounted

const Data = preload("res://game/catalogue.gd")
const SLOT = "user://pilot-v18.1.json"
const REWARDS = [
	["first", "sorties", 1, 400, ""],
	["first-win", "victories", 1, 0, "flarewing"],
	["intercept", "kills", 8, 750, "survey"],
	["flight-wing", "victories", 3, 470, "air-gripen"],
	["tideline", "distance", 20000, 0, "bronze-sky"],
]
var state: Dictionary

func _init(catalogue: RefCounted) -> void:
	state = {"credits":2600, "xp":0, "rewardedLevel":1, "selected":"j20", "unlocked":catalogue.source.startingFleet.duplicate(),
		"campaign":1, "completed":[], "improvements":{}, "loadouts":{}, "inventory":{"interceptor":1},
		"records":[], "claimed":[], "daily":{}, "sorties":0, "kills":0, "victories":0, "distance":0.0,
		"settings":{"fps":60, "quality":0.85, "sensitivity":1.0, "invert":false, "mute":false}}
	for path in [SLOT, SLOT + ".backup"]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and parsed.has("unlocked"):
			state.merge(parsed, true)
			break
	var migration_path := "user://v18-import.json"
	if not FileAccess.file_exists(SLOT) and FileAccess.file_exists(migration_path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(migration_path))
		if old is Dictionary and old.get("unlocked") is Array:
			for key in ["credits","xp","rewardedLevel","selected","unlocked","campaign","completed","improvements","loadouts","inventory","records","claimed","daily","sorties","kills","victories","distance"]:
				if not old.has(key):
					continue
				if typeof(state[key]) == TYPE_INT and (old[key] is float or old[key] is int):
					state[key] = maxi(0, int(old[key]))
				elif typeof(state[key]) == typeof(old[key]):
					state[key] = old[key]
			for key in ["sensitivity","invert","mute"]:
				state.settings[key] = old.get("settings", {}).get(key, state.settings[key])
			save()
	if not catalogue.planes.has(state.selected) or state.selected not in state.unlocked:
		state.selected = "j20"
	state.campaign = clampi(int(state.campaign), 1, 60)

func save() -> bool:
	var tmp := SLOT + ".pending"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(state))
	var status := file.get_error()
	file.close()
	if status != OK:
		return false
	if FileAccess.file_exists(SLOT):
		DirAccess.copy_absolute(SLOT, SLOT + ".backup")
	return DirAccess.rename_absolute(tmp, SLOT) == OK

func upgrade(part: String) -> String:
	var key: String = state.selected + ":" + part
	var old: int = int(state.improvements.get(key, 0))
	var price := 560 + old * 360
	if old >= 3:
		return "已达最高等级"
	if state.credits < price:
		return "信用点不足"
	state.credits -= price
	state.improvements[key] = old + 1
	if save():
		return "已完成改装"
	state.credits += price
	state.improvements[key] = old
	return "存档写入失败"

func select_plane(id: String) -> String:
	if id in state.unlocked:
		state.selected = id
		save()
		return ""
	var required: int = Data.UNLOCK_LEVELS.get(id, 1)
	if Data.level(int(state.xp)) < required:
		return "飞行员达到 Lv.%d 后解锁" % required
	if state.credits < 1150:
		return "需要 1,150 信用点"
	state.credits -= 1150
	state.unlocked.append(id)
	state.selected = id
	save()
	return "战机已解锁"

func equip(weapon_id: String) -> String:
	var price: int = Data.MISSILES[weapon_id].price
	if not state.inventory.has(weapon_id):
		if state.credits < price:
			return "信用点不足"
		state.credits -= price
		state.inventory[weapon_id] = 1
	if not state.loadouts.has(state.selected):
		state.loadouts[state.selected] = {}
	state.loadouts[state.selected].missile = weapon_id
	save()
	return "已挂载"

func level_of(part: String, id: String = "") -> int:
	return int(state.improvements.get((state.selected if id.is_empty() else id) + ":" + part, 0))

func selected_weapon(catalogue: RefCounted) -> String:
	var id: String = state.loadouts.get(state.selected, {}).get("missile", "interceptor")
	if Data.MISSILES.has(id) and catalogue.missile_compatible(catalogue.aircraft(state.selected), id):
		return id
	return "interceptor"

func debrief(result: Dictionary) -> void:
	state.credits += result.credits
	state.xp += result.xp
	state.sorties += 1
	state.kills += result.kills
	state.distance += result.distance
	if result.win:
		state.victories += 1
		if not result.id.is_empty() and result.id not in state.completed:
			state.completed.append(result.id)
		if result.campaign == int(state.campaign):
			state.campaign = mini(60, int(state.campaign) + 1)
	var level_now := Data.level(int(state.xp))
	for next in range(int(state.rewardedLevel) + 1, level_now + 1):
		state.credits += 160 + next * 36
		var unlocked: String = {4:"mirage", 8:"hornet", 12:"su35"}.get(next, "")
		if not unlocked.is_empty() and unlocked not in state.unlocked:
			state.unlocked.append(unlocked)
		if next == 6:
			state.inventory.flarewing = 1
	state.rewardedLevel = maxi(int(state.rewardedLevel), level_now)
	var reward_credits := _award_sortie_rewards(result)
	result["automatic_reward"] = reward_credits
	state.records.push_front(result)
	if state.records.size() > 36:
		state.records.resize(36)
	save()

func _award_sortie_rewards(result: Dictionary) -> int:
	var given := 0
	var date := Time.get_date_dict_from_system()
	var day := "%d-%d-%d" % [date.year, date.month, date.day]
	if state.daily.get("day") != day:
		state.daily = {"day":day, "sorties":0, "kills":0, "claimed":[]}
	state.daily.sorties += 1
	state.daily.kills += result.kills
	for daily in [["daily-sortie","sorties",1,150], ["daily-kills","kills",3,280]]:
		if daily[0] not in state.daily.claimed and state.daily[daily[1]] >= daily[2]:
			state.daily.claimed.append(daily[0])
			given += int(daily[3])
	for reward in REWARDS:
		if reward[0] in state.claimed or state[reward[1]] < reward[2]:
			continue
		state.claimed.append(reward[0])
		given += int(reward[3])
		var item: String = reward[4]
		if item.begins_with("air-"):
			item = item.trim_prefix("air-")
			if item not in state.unlocked:
				state.unlocked.append(item)
		elif not item.is_empty():
			state.inventory[item] = maxi(1, int(state.inventory.get(item, 0)))
	state.credits += given
	return given
