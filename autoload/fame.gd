extends Node
## Viewership. The dungeon is a show; you are content. Kills, bosses, and
## descents grow your audience (CHA multiplies gains — this replaces CHA's
## old loot-rarity bias). Milestone audiences mail you fan boxes.

const MILESTONES := [100, 500, 1000, 5000, 10000, 50000]
const MILESTONE_TIERS := [0, 1, 2, 2, 3, 3]

var viewers := 0
var next_milestone := 0


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.borough_boss_killed.connect(func() -> void: gain(250))
	Events.box_opened.connect(func(tier: int) -> void: gain(2 + tier * 3))
	Events.descended.connect(func(_turns: int) -> void: gain(100))
	Events.race_class_completed.connect(func() -> void: gain(150))
	Events.crush_survived.connect(func() -> void: gain(60))
	Events.level_up.connect(func(_level: int) -> void: gain(25))
	Events.achievement_unlocked.connect(func(_id: StringName, _t: String, _d: String) -> void: gain(50))


func _on_run_started() -> void:
	viewers = 3 + randi() % 15  # your mom is watching. maybe.
	next_milestone = 0
	Events.viewers_changed.emit(viewers)


## Every point of CHA over 8 adds 5% to viewer gains.
func multiplier() -> float:
	if GameState.character == null:
		return 1.0
	return 1.0 + maxi(GameState.character.get_stat(&"CHA") - 8, 0) * 0.05


func gain(base: int) -> int:
	var amount := int(round(base * multiplier()))
	viewers += amount
	Events.viewers_changed.emit(viewers)
	_check_milestones()
	if viewers >= 1000:
		Achievements.unlock(&"viewbait")
	if viewers >= 10000:
		Achievements.unlock(&"trending")
	return amount


func _on_enemy_killed(_def_id: StringName, is_boss: bool) -> void:
	gain(150 if is_boss else 3 + randi() % 4)


func _check_milestones() -> void:
	while next_milestone < MILESTONES.size() and viewers >= MILESTONES[next_milestone]:
		var tier: int = MILESTONE_TIERS[next_milestone]
		Events.announce.emit("VIEWER MILESTONE",
			"%d viewers! A fan box has been delivered. Try to look grateful." % MILESTONES[next_milestone])
		_deliver_fan_box(tier)
		next_milestone += 1


func _deliver_fan_box(tier: int) -> void:
	var c: CharacterData = GameState.character
	if c == null:
		return
	Events.msg("[color=%s]FAN BOX (%s)[/color] delivered. It smells like devotion." % [
		LootGenerator.TIER_COLORS[tier], LootGenerator.TIER_NAMES[tier]], &"loot")
	for item: ItemData in LootGenerator.open_box(tier, GameState.floor_number):
		c.inventory.append(item)
		Events.msg("  Fan mail: %s acquired." % item.colored_name(), &"loot")
	var gold := (tier + 1) * 15
	c.gold += gold
	Events.msg("  Fans also sent %d gold. And several unsettling letters." % gold, &"loot")
	Events.hud_refresh.emit()
