extends SceneTree

const Data = preload("res://game/catalogue.gd")
const Profile = preload("res://game/profile.gd")
const Battle = preload("res://game/battle.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var catalogue := Data.new()
	var profile := Profile.new(catalogue)
	var failures := []
	var waves := 0
	var kills := 0
	for stage in catalogue.source.campaign:
		seed(int(stage.campaign))
		var fight := Battle.new()
		root.add_child(fight)
		fight.setup(catalogue, profile, "campaign", stage, false)
		fight.set_physics_process(false)
		fight.set_process(false)
		var outcomes := []
		fight.finished.connect(func(row): outcomes.append(row))
		var good := true
		for expected in stage.engagement.waves:
			waves += 1
			good = good and fight.alive_enemies() == int(expected)
			# Deterministic firing range. Exercise the production damage, attribution and transition paths.
			fight.player.position.y = 2450.0
			fight.player.forward = Vector3.FORWARD
			fight.player.attitude = Quaternion.IDENTITY
			for other in fight.fleet:
				if other != fight.player:
					other.position.y = 3400.0
			for other in fight.fleet:
				if other == fight.player or other.hp <= 0.0:
					continue
				other.position = fight.player.position + Vector3.FORWARD * 90.0
				other.velocity = Vector3.ZERO
				for shot in 12:
					if other.hp <= 0.0:
						break
					fight._fire(fight.player, true, other)
					for step in 30:
						fight._update_shots(1.0 / 90.0)
				good = good and other.hp <= 0.0
				if other.hp > 0.0:
					break
			if not good:
				break
			fight._physics_process(1.0 / 90.0)
			good = good and fight.next_wave > fight.time
			fight.time = fight.next_wave
			fight._physics_process(1.0 / 90.0)
		kills += fight.player_kills
		if not good or outcomes.size() != 1 or not outcomes[0].win or outcomes[0].campaign != int(stage.campaign):
			failures.append(stage.campaign)
		fight.queue_free()
		await process_frame
	print(JSON.stringify({"missions":catalogue.source.campaign.size(),"waves":waves,"credited_kills":kills,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
