extends Node
## Achievement tracking. Unlocks persist across runs (user://achievements.json)
## because dying is temporary but shame is forever.

const SAVE_PATH := "user://achievements.json"

const DEFS := {
	&"first_blood": ["First Blood (It Was Probably a Rat)", "Kill your first monster."],
	&"exterminator": ["Pest Control Technician", "Kill 10 monsters in one run."],
	&"boss_slayer": ["Middle Management Removal", "Defeat a neighbourhood boss."],
	&"hostile_takeover": ["Hostile Takeover", "Clear every neighbourhood boss on a floor."],
	&"first_box": ["Baby's First Gambling Addiction", "Open a loot box."],
	&"whale": ["Certified Whale", "Open 8 loot boxes in one run."],
	&"fully_dressed": ["Dressed to Kill (Literally)", "Fill all five equipment slots."],
	&"fashion_icon": ["Fashion Icon", "Equip a Legendary item."],
	&"couponer": ["Extreme Couponing", "Buy something with 14+ Charisma."],
	&"pawn_regular": ["Pawn Shop Regular", "Sell 5 items in one run."],
	&"rebrand": ["Voluntary Biology", "Complete the race/class selection."],
	&"clutch": ["Cardio Paid Off", "Descend with 10 or fewer turns left on the floor timer."],
	&"ceiling_fan": ["Ceiling Appreciator", "Survive being crushed by a collapsing floor."],
	&"deep_dive": ["Prototype Depths Cleared", "Reach floor 5."],
	&"participation": ["Participation Award", "Die."],
}

var unlocked := {}  # id -> true, persistent
var run_unlocks := 0

## Per-run counters
var _run_kills := 0
var _run_boxes := 0
var _run_sells := 0


func _ready() -> void:
	_load()
	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.all_bosses_cleared.connect(func() -> void: unlock(&"hostile_takeover"))
	Events.box_opened.connect(_on_box_opened)
	Events.item_equipped.connect(_on_item_equipped)
	Events.item_bought.connect(_on_item_bought)
	Events.item_sold.connect(_on_item_sold)
	Events.descended.connect(_on_descended)
	Events.crush_survived.connect(func() -> void: unlock(&"ceiling_fan"))
	Events.race_class_completed.connect(func() -> void: unlock(&"rebrand"))
	Events.floor_changed.connect(_on_floor_changed)
	Events.player_died.connect(func() -> void: unlock(&"participation"))


func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


func unlock(id: StringName) -> void:
	if unlocked.has(id) or not DEFS.has(id):
		return
	unlocked[id] = true
	run_unlocks += 1
	_save()
	Events.msg("ACHIEVEMENT UNLOCKED: %s — %s" % [DEFS[id][0], DEFS[id][1]], &"system")


func _on_run_started() -> void:
	run_unlocks = 0
	_run_kills = 0
	_run_boxes = 0
	_run_sells = 0


func _on_enemy_killed(_def_id: StringName, is_boss: bool) -> void:
	_run_kills += 1
	unlock(&"first_blood")
	if _run_kills >= 10:
		unlock(&"exterminator")
	if is_boss:
		unlock(&"boss_slayer")


func _on_box_opened(_tier: int) -> void:
	_run_boxes += 1
	unlock(&"first_box")
	if _run_boxes >= 8:
		unlock(&"whale")


func _on_item_equipped(item: ItemData) -> void:
	if item.rarity == ItemData.Rarity.LEGENDARY:
		unlock(&"fashion_icon")
	var c: CharacterData = GameState.character
	var filled := true
	for slot in c.equipment:
		if c.equipment[slot] == null:
			filled = false
	if filled:
		unlock(&"fully_dressed")


func _on_item_bought(cha: int) -> void:
	if cha >= 14:
		unlock(&"couponer")


func _on_item_sold() -> void:
	_run_sells += 1
	if _run_sells >= 5:
		unlock(&"pawn_regular")


func _on_descended(turns_remaining: int) -> void:
	if turns_remaining <= 10:
		unlock(&"clutch")


func _on_floor_changed(floor_number: int) -> void:
	if floor_number >= 5:
		unlock(&"deep_dive")


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(unlocked.keys().map(func(k: StringName) -> String: return String(k))))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Array:
		for id in data:
			unlocked[StringName(id)] = true
