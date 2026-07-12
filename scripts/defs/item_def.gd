class_name ItemDef
extends Resource
## Base item definition. Authored in the all() code table.

var id: StringName
var display_name: String
var slot: StringName  # &"weapon" &"head" &"chest" &"feet" &"trinket" &"consumable"
var damage := 0
var defense := 0
var base_bonus := {}  # e.g. { &"CHA": 1 } — innate stat bonus (trinkets)
var flavor_text := ""
var min_floor := 1


static func make(d: Dictionary) -> ItemDef:
	var it := ItemDef.new()
	for key in d:
		it.set(key, d[key])
	return it


static func all() -> Array[ItemDef]:
	var defs: Array[ItemDef] = []
	for d: Dictionary in [
		# --- Weapons ---
		{ "id": &"crawler_baton", "display_name": "Crawler Baton", "slot": &"weapon", "damage": 3,
			"flavor_text": "Standard issue. The System denies it was ever a mop handle.", "min_floor": 1 },
		{ "id": &"rusty_sword", "display_name": "Rusty Sword", "slot": &"weapon", "damage": 4,
			"flavor_text": "The System's warranty does not cover tetanus.", "min_floor": 1 },
		{ "id": &"meat_cleaver", "display_name": "Meat Cleaver", "slot": &"weapon", "damage": 5,
			"flavor_text": "Previously owned by a chef with anger management issues.", "min_floor": 2 },
		{ "id": &"spiked_gauntlets", "display_name": "Spiked Gauntlets", "slot": &"weapon", "damage": 6,
			"flavor_text": "Punch things. But, like, professionally.", "min_floor": 3 },
		{ "id": &"vorpal_letter_opener", "display_name": "Vorpal Letter Opener", "slot": &"weapon", "damage": 8,
			"flavor_text": "Opens mail, arteries, and existential questions.", "min_floor": 4 },
		# --- Head ---
		{ "id": &"pot_helm", "display_name": "Pot Helm", "slot": &"head", "defense": 1,
			"flavor_text": "Smells like soup. Will always smell like soup.", "min_floor": 1 },
		{ "id": &"riot_helmet", "display_name": "Riot Helmet", "slot": &"head", "defense": 2,
			"flavor_text": "Crowd control, but the crowd is monsters.", "min_floor": 3 },
		# --- Chest ---
		{ "id": &"bathrobe", "display_name": "Fluffy Bathrobe", "slot": &"chest", "defense": 1,
			"flavor_text": "Peak crawler fashion. The viewers love it.", "min_floor": 1 },
		{ "id": &"leather_vest", "display_name": "Leather Vest", "slot": &"chest", "defense": 2,
			"flavor_text": "Distressed leather. The distress is fresh and it is yours.", "min_floor": 2 },
		{ "id": &"cast_iron_cuirass", "display_name": "Cast Iron Cuirass", "slot": &"chest", "defense": 3,
			"flavor_text": "Pre-seasoned. Do not wash with soap.", "min_floor": 3 },
		# --- Feet ---
		{ "id": &"worn_crocs", "display_name": "Worn Crocs", "slot": &"feet", "defense": 1,
			"flavor_text": "Sport mode engaged.", "min_floor": 1 },
		{ "id": &"steel_toe_boots", "display_name": "Steel-Toe Boots", "slot": &"feet", "defense": 2,
			"flavor_text": "OSHA-compliant. The dungeon is not.", "min_floor": 2 },
		# --- Trinkets ---
		{ "id": &"participation_medal", "display_name": "Participation Medal", "slot": &"trinket",
			"base_bonus": { &"CHA": 1 },
			"flavor_text": "You showed up! Statistically, that's the hard part.", "min_floor": 1 },
		{ "id": &"lucky_rabbit_foot", "display_name": "Lucky Rabbit's Foot", "slot": &"trinket",
			"base_bonus": { &"DEX": 1 },
			"flavor_text": "Less lucky for the rabbit.", "min_floor": 1 },
		# --- Consumables ---
		{ "id": &"healing_potion", "display_name": "Healing Potion", "slot": &"consumable",
			"flavor_text": "Tastes like blue Gatorade and regret.", "min_floor": 1 },
	]:
		defs.append(make(d))
	return defs
