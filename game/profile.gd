extends RefCounted

const Data = preload("res://game/catalogue.gd")
const SLOT = "user://pilot-v18.2.json"
const SCHEMA := 182
const MODES := ["campaign", "training", "free"]
const DAILY_REWARDS = [["daily-sortie", "sorties", 1, 150, ""], ["daily-kills", "kills", 3, 280, ""]]
const LEVEL_GIFTS = {4:"air-mirage", 6:"flarewing", 8:"air-hornet", 12:"air-su35"}
const REWARDS = [
	["first", "sorties", 1, 400, ""],
	["first-win", "victories", 1, 0, "flarewing"],
	["intercept", "kills", 8, 750, ""],
	["flight-wing", "victories", 3, 470, "air-gripen"],
	["tideline", "distance", 20000, 0, ""],
]
var state: Dictionary
var aircraft_data: RefCounted
var storage_slot: String

func _init(catalogue: RefCounted, location := SLOT) -> void:
	aircraft_data = catalogue
	storage_slot = location
	state = {"credits":2600, "xp":0, "rewardedLevel":1, "selected":"j20", "unlocked":catalogue.source.startingFleet.duplicate(),
		"campaign":1, "completed":[], "improvements":{}, "loadouts":{}, "inventory":{"interceptor":1},
		"records":[], "claimed":[], "daily":{}, "sorties":0, "kills":0, "victories":0, "distance":0.0, "modes":{},
		"settings":{"fps":60, "quality":0.85, "sensitivity":1.0, "invert":false, "mute":false}}
	var candidates := [storage_slot, storage_slot + ".backup"]
	if storage_slot == SLOT:
		candidates.append_array(["user://pilot-v18.1.json", "user://pilot-v18.1.json.backup", "user://v18-import.json"])
	if storage_slot == SLOT and OS.get_name() == "Linux":
		var desktop := OS.get_data_dir().path_join("godot/app_userdata/苍穹锋刃 V18.1")
		candidates.append(desktop.path_join("pilot-v18.1.json"))
		candidates.append(desktop.path_join("pilot-v18.1.json.backup"))
	for path in candidates:
		var old := _read(path, path.begins_with(storage_slot))
		if not old.is_empty():
			_merge_profile(old)
			if path != storage_slot:
				save()
			break

func _read(path: String, envelope: bool) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	if envelope:
		var body: Variant = parsed.get("payload")
		if parsed.get("schema") != SCHEMA or not body is String or parsed.get("checksum") != body.sha256_text():
			return {}
		parsed = JSON.parse_string(body)
	if not parsed is Dictionary or not parsed.get("unlocked") is Array or not parsed.get("credits") is float:
		return {}
	return parsed

func _merge_profile(old: Dictionary) -> void:
	for key in state:
		if not old.has(key):
			continue
		if state[key] is int and old[key] is float and is_finite(old[key]):
			state[key] = maxi(0, int(old[key]))
		elif key != "settings" and typeof(old[key]) == typeof(state[key]):
			state[key] = old[key]
	var valid_fleet: Array = aircraft_data.source.startingFleet.duplicate()
	for id in state.unlocked:
		if id is String and aircraft_data.planes.has(id) and id not in valid_fleet:
			valid_fleet.append(id)
	state.unlocked = valid_fleet
	if state.selected not in state.unlocked:
		state.selected = "j20"
	state.campaign = clampi(int(state.campaign), 1, 60)
	var settings: Variant = old.get("settings")
	if settings is Dictionary:
		for key in ["invert", "mute"]:
			if settings.get(key) is bool:
				state.settings[key] = settings[key]
		if settings.get("fps") == 90:
			state.settings.fps = 90
		if settings.get("quality") is float:
			state.settings.quality = clampf(settings.quality, 0.67, 1.0)
		if settings.get("sensitivity") is float:
			state.settings.sensitivity = clampf(settings.sensitivity, 0.45, 1.8)
	for id in state.inventory.keys():
		if not Data.MISSILES.has(id):
			state.inventory.erase(id)
	state.records = state.records.filter(func(entry): return entry is Dictionary and entry.get("name") is String and entry.get("grade") is String and entry.get("score") is float)
	if state.records.size() > 36:
		state.records.resize(36)
	if state.modes.is_empty():
		for record in state.records:
			var mode := _result_mode(record)
			var stats := _mode_stats(mode)
			stats.sorties += 1
			stats.kills += maxi(0, int(record.get("kills", 0)))
			stats.victories += int(bool(record.get("win", false)))
			stats.deaths += maxi(0, int(record.get("deaths", 0)))
			state.modes[mode] = stats

func save() -> bool:
	var payload := JSON.stringify(state)
	var envelope := JSON.stringify({"schema":SCHEMA, "payload":payload, "checksum":payload.sha256_text()})
	var pending := storage_slot + ".pending"
	if not _write_text(pending, envelope):
		return false
	if not _read(storage_slot, true).is_empty():
		var backup := storage_slot + ".backup"
		if not _write_text(backup + ".pending", FileAccess.get_file_as_string(storage_slot)):
			return false
		if DirAccess.rename_absolute(backup + ".pending", backup) != OK:
			return false
	return DirAccess.rename_absolute(pending, storage_slot) == OK

func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(content)
	file.flush()
	var status := file.get_error()
	file.close()
	return status == OK

func _commit(before: Dictionary) -> bool:
	if save():
		return true
	state = before
	return false

func set_option(key: String, value: Variant) -> bool:
	if not state.settings.has(key):
		return false
	var before := state.duplicate(true)
	state.settings[key] = value
	return _commit(before)

func upgrade(part: String) -> String:
	if not Data.UPGRADE_LABELS.has(part):
		return "改装项目不可用"
	var key: String = state.selected + ":" + part
	var old: int = int(state.improvements.get(key, 0))
	var price := Data.upgrade_price(old)
	if old >= Data.UPGRADE_LIMIT:
		return "已达最高等级"
	if state.credits < price:
		return "信用点不足"
	var before := state.duplicate(true)
	state.credits -= price
	state.improvements[key] = old + 1
	return "已完成改装" if _commit(before) else "存档写入失败"

func select_plane(id: String) -> String:
	if not aircraft_data.planes.has(id) or aircraft_data.aircraft(id).support:
		return "战机不可用"
	var before := state.duplicate(true)
	if id in state.unlocked:
		state.selected = id
		return "" if _commit(before) else "存档写入失败"
	var required: int = Data.UNLOCK_LEVELS.get(id, 1)
	if Data.level(int(state.xp)) < required:
		return "飞行员达到等级 %d 后解锁" % required
	if state.credits < Data.AIRCRAFT_PRICE:
		return "需要 %d 信用点" % Data.AIRCRAFT_PRICE
	state.credits -= Data.AIRCRAFT_PRICE
	_grant("air-" + id)
	state.selected = id
	return "战机已解锁" if _commit(before) else "存档写入失败"

func equip(weapon_id: String) -> String:
	if not Data.MISSILES.has(weapon_id) or not aircraft_data.missile_compatible(aircraft_data.aircraft(state.selected), weapon_id):
		return "当前机型无法挂载"
	var price: int = Data.MISSILES[weapon_id].price
	var before := state.duplicate(true)
	if not state.inventory.has(weapon_id):
		if state.credits < price:
			return "信用点不足"
		state.credits -= price
		state.inventory[weapon_id] = 1
	if not state.loadouts.has(state.selected) or not state.loadouts[state.selected] is Dictionary:
		state.loadouts[state.selected] = {}
	state.loadouts[state.selected].missile = weapon_id
	return "已挂载" if _commit(before) else "存档写入失败"

func level_of(part: String, id: String = "") -> int:
	return int(state.improvements.get((state.selected if id.is_empty() else id) + ":" + part, 0))

func selected_weapon() -> String:
	var saved: Variant = state.loadouts.get(state.selected)
	var id: String = str(saved.get("missile", "interceptor")) if saved is Dictionary else str(saved)
	if Data.MISSILES.has(id) and aircraft_data.missile_compatible(aircraft_data.aircraft(state.selected), id):
		return id
	return "interceptor"

func _result_mode(result: Dictionary) -> String:
	var mode: String = str(result.get("mode", ""))
	if mode in MODES:
		return mode
	if str(result.get("id", "")).begins_with("training_"):
		return "training"
	return "campaign" if int(result.get("campaign", 0)) > 0 else "free"

func _mode_stats(mode: String) -> Dictionary:
	var count := {"sorties":0, "kills":0, "deaths":0, "victories":0, "aborts":0}
	var old: Variant = state.modes.get(mode)
	if old is Dictionary:
		for key in count:
			count[key] = int(old.get(key, 0))
	return count

func abort(mode: String) -> void:
	if mode not in MODES:
		return
	var before := state.duplicate(true)
	var count := _mode_stats(mode)
	count.aborts += 1
	state.modes[mode] = count
	_commit(before)

func debrief(result: Dictionary) -> bool:
	var before := state.duplicate(true)
	var mode := _result_mode(result)
	var count := _mode_stats(mode)
	count.sorties += 1
	count.kills += result.kills
	count.deaths += result.deaths
	count.victories += int(result.win)
	state.modes[mode] = count
	var eligible: bool = result.get("eligible", true)
	if mode == "training" and (not result.win or result.id in state.completed):
		eligible = false
	if not eligible:
		result.credits = 0
		result.xp = 0
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
		_grant(LEVEL_GIFTS.get(next, ""))
	state.rewardedLevel = maxi(int(state.rewardedLevel), level_now)
	var reward_credits := _award_sortie_rewards(result) if eligible and mode != "training" else 0
	result["automatic_reward"] = reward_credits
	state.records.push_front(result.duplicate(true))
	if state.records.size() > 36:
		state.records.resize(36)
	var committed := _commit(before)
	if not committed:
		result.credits = 0
		result.xp = 0
		result.automatic_reward = 0
	return committed

func _award_sortie_rewards(result: Dictionary) -> int:
	var date := Time.get_date_dict_from_system()
	var day := "%d-%d-%d" % [date.year, date.month, date.day]
	if state.daily.get("day") != day:
		state.daily = {"day":day, "sorties":0, "kills":0, "claimed":[]}
	state.daily.sorties += 1
	state.daily.kills += result.kills
	var given := _claim_rewards(DAILY_REWARDS, state.daily) + _claim_rewards(REWARDS, state)
	state.credits += given
	return given

func _claim_rewards(rules: Array, ledger: Dictionary) -> int:
	var given := 0
	for rule in rules:
		if rule[0] not in ledger.claimed and ledger[rule[1]] >= rule[2]:
			ledger.claimed.append(rule[0])
			given += int(rule[3])
			_grant(rule[4])
	return given

func _grant(item: String) -> void:
	if item.begins_with("air-"):
		var aircraft := item.trim_prefix("air-")
		if aircraft not in state.unlocked:
			state.unlocked.append(aircraft)
	elif not item.is_empty():
		state.inventory[item] = maxi(1, int(state.inventory.get(item, 0)))
