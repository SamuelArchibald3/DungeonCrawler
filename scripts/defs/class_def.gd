class_name ClassDef
extends Resource
## Class option offered at the level-3 selection event.

var id: StringName
var display_name: String
var stat_mods := {}
var max_hp_mod := 0
var ability_id: StringName
var description := ""


static func make(d: Dictionary) -> ClassDef:
	var c := ClassDef.new()
	for key in d:
		c.set(key, d[key])
	return c


static func all() -> Array[ClassDef]:
	var defs: Array[ClassDef] = []
	for d: Dictionary in [
		{
			"id": &"brawler", "display_name": "Brawler",
			"stat_mods": { &"STR": 2, &"CON": 1 },
			"ability_id": &"power_slam",
			"description": "You solve problems with your hands. The problems are increasingly weird, but so are your hands.",
		},
		{
			"id": &"shadow_rogue", "display_name": "Shadow Rogue",
			"stat_mods": { &"DEX": 3 },
			"ability_id": &"backstab",
			"description": "Sneaky, stabby, and contractually required to say 'nothing personnel.' Comes with free dramatic exits.",
		},
		{
			"id": &"hedge_wizard", "display_name": "Hedge Wizard",
			"stat_mods": { &"INT": 3 },
			"ability_id": &"power_slam",
			"description": "Studied magic from a correspondence course. The hedge is metaphorical. The explosions are not.",
		},
		{
			"id": &"meat_shield", "display_name": "Meat Shield",
			"stat_mods": { &"CON": 3 }, "max_hp_mod": 8,
			"ability_id": &"thick_skin",
			"description": "Someone has to stand in front. The System admires your commitment to being in the way.",
		},
		{
			"id": &"cult_leader", "display_name": "Cult Leader",
			"stat_mods": { &"CHA": 3, &"INT": 1 },
			"ability_id": &"heal_pulse",
			"description": "Charisma so potent it's classified as a controlled substance on four planets. Robes sold separately.",
		},
		{
			"id": &"speedrunner", "display_name": "Speedrunner",
			"stat_mods": { &"DEX": 2, &"CHA": 1 },
			"ability_id": &"smoke_step",
			"description": "Any% dungeon completion. Skips cutscenes, dialogue, and occasionally the laws of physics.",
		},
	]:
		defs.append(make(d))
	return defs
