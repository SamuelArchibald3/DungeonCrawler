class_name RaceDef
extends Resource
## Race option offered at the level-3 selection event. Sales-pitch tone —
## the System is trying to close a deal.

var id: StringName
var display_name: String
var stat_mods := {}
var max_hp_mod := 0
var ability_id: StringName
var description := ""


static func make(d: Dictionary) -> RaceDef:
	var r := RaceDef.new()
	for key in d:
		r.set(key, d[key])
	return r


static func all() -> Array[RaceDef]:
	var defs: Array[RaceDef] = []
	for d: Dictionary in [
		{
			"id": &"rock_golemoid", "display_name": "Rock Golemoid",
			"stat_mods": { &"STR": 3, &"CON": 2, &"DEX": -2 }, "max_hp_mod": 10,
			"ability_id": &"thick_skin",
			"description": "Skin like granite! Personality like granite! Everything like granite! Showers become exfoliation events.",
		},
		{
			"id": &"feline_primal", "display_name": "Feline Primal",
			"stat_mods": { &"DEX": 3, &"CHA": 1, &"CON": -1 },
			"ability_id": &"backstab",
			"description": "Reflexes of a cat, attitude of a cat, employability of a cat. Warranty voided by laser pointers.",
		},
		{
			"id": &"bopca", "display_name": "Bopca",
			"stat_mods": { &"INT": 2, &"CHA": 3, &"STR": -1 },
			"ability_id": &"heal_pulse",
			"description": "Small, big-eared, disturbingly good at retail. Comes with an innate sense of markup.",
		},
		{
			"id": &"swamp_crocodilian", "display_name": "Swamp Crocodilian",
			"stat_mods": { &"STR": 2, &"CON": 3, &"CHA": -2 }, "max_hp_mod": 6,
			"ability_id": &"thick_skin",
			"description": "Apex predator of any body of water and most hot tubs. Smile rated 9/10 by dentists who then fled.",
		},
		{
			"id": &"half_elf_influencer", "display_name": "Half-Elf Influencer",
			"stat_mods": { &"CHA": 4, &"DEX": 1, &"CON": -1 },
			"ability_id": &"smoke_step",
			"description": "Pointy ears, perfect cheekbones, sponsored by at least three galactic brands you've never heard of.",
		},
		{
			"id": &"dungeon_gnome", "display_name": "Dungeon Gnome",
			"stat_mods": { &"INT": 3, &"DEX": 2, &"STR": -2 },
			"ability_id": &"power_slam",
			"description": "Tiny, furious, and legally considered a trip hazard. Ships with unlicensed explosives knowledge.",
		},
	]:
		defs.append(make(d))
	return defs
