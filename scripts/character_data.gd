class_name CharacterData
extends Resource
## The crawler. Pure data — scenes render it, combat.gd computes with it.
## Stats are always queried through get_stat() (base + race + class + gear),
## never cached.

const STAT_NAMES: Array[StringName] = [&"STR", &"DEX", &"CON", &"INT", &"CHA"]
const EQUIP_SLOTS: Array[StringName] = [&"weapon", &"head", &"chest", &"feet", &"trinket"]

var char_name: String = "Test Crawler"
var base_stats := { &"STR": 8, &"DEX": 8, &"CON": 8, &"INT": 8, &"CHA": 8 }
var race: Resource = null        # RaceDef, null until the selection event
var char_class: Resource = null  # ClassDef
var level := 1
var xp := 0
var gold := 0
var unspent_stat_points := 0  # +2 per level; allocatable only in saferooms
var bonus_max_hp := 0  # flat bonuses (e.g. saferoom cot naps)
var hp := 0
var max_hp := 0
var inventory: Array = []        # Array[ItemData]
var equipment := {
	&"weapon": null, &"head": null, &"chest": null, &"feet": null, &"trinket": null,
}
var abilities: Array[StringName] = []
var ability_cooldowns := {}      # ability id -> turns remaining


func _init() -> void:
	recompute_max_hp()
	hp = max_hp


func get_stat(stat: StringName) -> int:
	var total: int = base_stats.get(stat, 0)
	if race != null:
		total += race.stat_mods.get(stat, 0)
	if char_class != null:
		total += char_class.stat_mods.get(stat, 0)
	return total + get_gear_bonus(stat)


## The equipment's share of a stat, shown separately in the character sheet.
func get_gear_bonus(stat: StringName) -> int:
	var total := 0
	for slot in equipment:
		var item = equipment[slot]
		if item != null:
			total += item.get_stat_bonus(stat)
	return total


func recompute_max_hp() -> void:
	var new_max := 10 + get_stat(&"CON") * 3 + level * 2 + bonus_max_hp
	if race != null:
		new_max += race.max_hp_mod
	if char_class != null:
		new_max += char_class.max_hp_mod
	var lost := max_hp - hp
	max_hp = new_max
	hp = clampi(max_hp - lost, 1, max_hp)


func xp_to_next() -> int:
	return level * 10


## Returns true if a level was gained.
func gain_xp(amount: int) -> bool:
	xp += amount
	var leveled := false
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		unspent_stat_points += 2
		leveled = true
		recompute_max_hp()
		hp = max_hp  # prototype-generous: full heal on level-up
	return leveled


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)


## Total defense from equipped gear (items expose get_defense()).
func get_defense() -> int:
	var total := 0
	for slot in equipment:
		var item = equipment[slot]
		if item != null:
			total += item.get_defense()
	return total


## Weapon damage, or 2 unarmed ("you have fists, technically").
func get_weapon_damage() -> int:
	var weapon = equipment[&"weapon"]
	return weapon.get_damage() if weapon != null else 2


func has_ability(id: StringName) -> bool:
	return abilities.has(id)
