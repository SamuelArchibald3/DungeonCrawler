class_name EnemyDef
extends Resource
## Enemy archetype. Defs live in code tables (see all()) rather than .tres
## files so they can be authored without the editor; convert later if desired.

var id: StringName
var display_name: String
var glyph: String
var color: Color
var max_hp: int
var attack: int
var defense: int
var xp: int
var move_every_n_turns: int = 1
var aggro_range: int = 8
var drop_chance: float = 0.0
var min_floor: int = 1
var telegraphs := false  # heavy hitters wind up one action before striking
var ranged := false      # attacks from distance along line of sight
var attack_range: int = 4
var poison_chance := 0.0  # chance per landed hit to poison the player


static func make(d: Dictionary) -> EnemyDef:
	var e := EnemyDef.new()
	for key in d:
		e.set(key, d[key])
	return e


static func all() -> Array[EnemyDef]:
	var defs: Array[EnemyDef] = []
	for d: Dictionary in [
		{
			"id": &"rat", "display_name": "Dungeon Rat", "glyph": "r",
			"color": Color(0.76, 0.6, 0.42),
			"max_hp": 6, "attack": 2, "defense": 0, "xp": 3,
			"move_every_n_turns": 1, "aggro_range": 6, "drop_chance": 0.08,
			"min_floor": 1, "poison_chance": 0.25,
		},
		{
			"id": &"goblin", "display_name": "Goblin", "glyph": "g",
			"color": Color(0.45, 0.78, 0.35),
			"max_hp": 12, "attack": 3, "defense": 1, "xp": 6,
			"move_every_n_turns": 1, "aggro_range": 8, "drop_chance": 0.25,
			"min_floor": 1,
		},
		{
			"id": &"skeleton_brute", "display_name": "Skeleton Brute", "glyph": "S",
			"color": Color(0.85, 0.85, 0.8),
			"max_hp": 22, "attack": 6, "defense": 2, "xp": 12,
			"move_every_n_turns": 2, "aggro_range": 5, "drop_chance": 0.35,
			"min_floor": 2, "telegraphs": true,
		},
		{
			"id": &"goblin_spitter", "display_name": "Goblin Spitter", "glyph": "s",
			"color": Color(0.65, 0.9, 0.3),
			"max_hp": 9, "attack": 3, "defense": 0, "xp": 8,
			"move_every_n_turns": 1, "aggro_range": 9, "drop_chance": 0.2,
			"min_floor": 2, "ranged": true, "attack_range": 4, "poison_chance": 0.35,
		},
		{
			"id": &"hobgoblin", "display_name": "Hobgoblin Enforcer", "glyph": "H",
			"color": Color(0.85, 0.55, 0.25),
			"max_hp": 18, "attack": 5, "defense": 1, "xp": 10,
			"move_every_n_turns": 1, "aggro_range": 9, "drop_chance": 0.3,
			"min_floor": 3,
		},
		{
			"id": &"crypt_horror", "display_name": "Crypt Horror", "glyph": "C",
			"color": Color(0.6, 0.35, 0.75),
			"max_hp": 32, "attack": 8, "defense": 3, "xp": 18,
			"move_every_n_turns": 1, "aggro_range": 6, "drop_chance": 0.45,
			"min_floor": 4, "telegraphs": true,
		},
	]:
		defs.append(make(d))
	return defs
