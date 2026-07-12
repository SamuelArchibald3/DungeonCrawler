extends Node
## Floor quests, offered and claimed at the saferoom guide. One per floor.

enum QState { NONE, OFFERED, ACTIVE, COMPLETE, CLAIMED }

var state: int = QState.NONE
var data := {}  # type ("kill"/"boss"/"boxes"), target_def, target_name, needed, count, reward_gold, desc


func _ready() -> void:
	Events.floor_changed.connect(func(_n: int) -> void: _reset())
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.box_opened.connect(_on_box_opened)


func _reset() -> void:
	state = QState.NONE
	data = {}


## Rolls this floor's quest from the dungeon's neighbourhoods. Idempotent.
func offer(dungeon: Dungeon) -> void:
	if state != QState.NONE or dungeon == null or not is_instance_valid(dungeon):
		return
	var rng := GameState.rng
	var floor_num: int = GameState.floor_number
	var roll := rng.randf()

	if roll < 0.4 and not dungeon.zones_runtime.is_empty():
		var zone: Dictionary = dungeon.zones_runtime[rng.randi_range(0, dungeon.zones_runtime.size() - 1)]
		var def: EnemyDef = zone["def"]
		var needed := 3 + floor_num
		data = {
			"type": "kill", "target_def": def.id, "target_name": def.display_name,
			"needed": needed, "count": 0, "reward_gold": 40 + floor_num * 15,
			"desc": "Cull %d %ss. The HOA has spoken." % [needed, def.display_name],
		}
	elif roll < 0.7 and _find_living_boss(dungeon) != null:
		var boss: Entity = _find_living_boss(dungeon)
		data = {
			"type": "boss", "target_def": boss.enemy_def.id, "target_name": boss.boss_name,
			"needed": 1, "count": 0, "reward_gold": 60 + floor_num * 25,
			"desc": "Evict %s from %s. Bring receipts." % [boss.boss_name, dungeon.zone_name(boss.zone_index)],
		}
	else:
		var needed := 2 + (1 if floor_num >= 3 else 0)
		data = {
			"type": "boxes", "target_def": &"", "target_name": "loot box",
			"needed": needed, "count": 0, "reward_gold": 30 + floor_num * 10,
			"desc": "Open %d loot boxes. For science. And sponsorship." % needed,
		}
	state = QState.OFFERED


func _find_living_boss(dungeon: Dungeon) -> Entity:
	for info: Dictionary in dungeon.zones_runtime:
		var boss: Variant = info["boss"]
		if boss != null and is_instance_valid(boss) and boss.hp > 0:
			return boss
	return null


func accept() -> void:
	if state != QState.OFFERED:
		return
	state = QState.ACTIVE
	Events.msg("QUEST ACCEPTED: %s" % data["desc"], &"system")
	Events.hud_refresh.emit()


func claim() -> void:
	if state != QState.COMPLETE:
		return
	state = QState.CLAIMED
	GameState.character.gold += data["reward_gold"]
	Events.msg("QUEST REWARD: +%d gold. The guide stamps something aggressively." % data["reward_gold"], &"loot")
	Events.hud_refresh.emit()


func status_line() -> String:
	match state:
		QState.ACTIVE:
			return "Quest: %s (%d/%d)" % [data["target_name"], data["count"], data["needed"]]
		QState.COMPLETE:
			return "Quest COMPLETE — visit a guide (?)"
		_:
			return ""


func _progress(amount: int = 1) -> void:
	if state != QState.ACTIVE:
		return
	data["count"] = mini(data["count"] + amount, data["needed"])
	if data["count"] >= data["needed"]:
		state = QState.COMPLETE
		Events.msg("QUEST COMPLETE: %s — return to a guide (?) for payment." % data["desc"], &"system")
	else:
		Events.msg("Quest progress: %d/%d." % [data["count"], data["needed"]], &"info")
	Events.hud_refresh.emit()


func _on_enemy_killed(def_id: StringName, is_boss: bool) -> void:
	if state != QState.ACTIVE:
		return
	match data["type"]:
		"kill":
			if def_id == data["target_def"] and not is_boss:
				_progress()
		"boss":
			if is_boss and def_id == data["target_def"]:
				_progress()


func _on_box_opened(_tier: int) -> void:
	if state == QState.ACTIVE and data["type"] == "boxes":
		_progress()
