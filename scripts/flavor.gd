class_name Flavor
extends RefCounted
## All flavor strings in one place so a future re-theme is cheap.

const NAME_FIRST := [
	"Chad", "Princess", "Meat", "Gravy", "Tortellini", "Blaze", "Kevin",
	"Doris", "Butters", "Mongo", "Sasha", "Tank", "Beverly", "Chomps",
	"Randall", "Peaches", "Diesel", "Mildred",
]

const NAME_LAST := [
	"McStabby", "the Unwashed", "Bologna", "Two-Socks", "von Crouton",
	"the Damp", "Skullcrusher", "Papercut", "the Third", "O'Ruin",
	"Basementborn", "the Refundable", "Hamfist", "of the HOA",
]

const EULOGIES := [
	"The System notes your performance was 'technically a performance.'",
	"Your death has been clipped, remixed, and set to royalty-free dubstep.",
	"A moment of silence was scheduled, then sold to a sponsor.",
	"Cause of death: dungeon. The coroner was not paid enough to elaborate.",
	"Your fans (both of them) are devastated.",
	"The System has awarded you the 'Stopped Being Alive' achievement.",
	"Merchandise featuring your final scream is already sold out.",
]

const CARL_NEWS := [
	"BREAKING: Crawler 'Carl' has destroyed something load-bearing again.",
	"NEWS: Carl's cat remains more popular than you. By a lot.",
	"ALERT: Floor-wide explosion attributed to a barefoot man with a positive attitude.",
	"TRENDING: #FeetGuy is once again the top crawler hashtag.",
	"NEWS: The Syndicate denies that Carl is 'a problem.' Sources say otherwise.",
	"UPDATE: Property damage records broken on a floor you are not on.",
]

const BOX_QUIPS := [
	"The System hopes you enjoy your complimentary dopamine.",
	"Contents settled during interdimensional shipping.",
	"This box was watched by 1.2 million viewers. No pressure.",
	"Sponsored by a company that no longer exists.",
	"The box thanks you for freeing it from its crushing purpose.",
]

const WELCOME_LINES := [
	"Welcome to the Dungeon, %s. Your survival is not anticipated.",
	"Crawler %s has entered the dungeon. Viewership: negligible.",
	"%s joins the crawl. The odds have been calculated and laughed at.",
]


const ZONE_NAMES := {
	&"rat": ["The Rat Warrens", "Whisker Alley", "The Squeaklands"],
	&"goblin": ["Goblin Flea Market", "Snotgrease Row", "Little Gobtown"],
	&"skeleton_brute": ["The Bone Yard", "Femur Heights", "Calcium Corner"],
	&"hobgoblin": ["Enforcer District", "Kneecap Plaza", "Protection Racket Row"],
	&"crypt_horror": ["The Purple Quarter", "Mausoleum Mile", "The Moist Dark"],
}

const BOSS_NAMES := {
	&"rat": "The Rat King",
	&"goblin": "Goblin Kingpin",
	&"skeleton_brute": "The Bone Foreman",
	&"hobgoblin": "Chief Kneecapper",
	&"crypt_horror": "Regional Crypt Manager",
}


static func zone_name(def_id: StringName, rng: RandomNumberGenerator) -> String:
	var names: Array = ZONE_NAMES.get(def_id, ["The Unzoned District"])
	return names[rng.randi_range(0, names.size() - 1)]


static func boss_name(def_id: StringName) -> String:
	return BOSS_NAMES.get(def_id, "Middle Manager")


const BOROUGH_BOSS_NAMES := [
	"Grull, Borough Landlord",
	"The Rent Collector",
	"Magnus Fleshpile, Zoning Commissioner",
	"Her Dampness, Baroness of Mildew",
	"Chairman Gnash",
	"Big Lorraine, Stairwell Cartel Boss",
	"Deputy Mayor Chewface",
]


static func borough_boss_name(rng: RandomNumberGenerator) -> String:
	return BOROUGH_BOSS_NAMES[rng.randi_range(0, BOROUGH_BOSS_NAMES.size() - 1)]


const SHOP_GREETINGS := [
	"The Bopca beams: 'A customer! A live one, even!'",
	"'Welcome, welcome. Everything is authentic. Some of it is even safe.'",
	"'Ah, a crawler with gold. My favorite species.'",
	"'No refunds, no warranties, no eye contact with the merchandise.'",
]


static func shop_greeting() -> String:
	return SHOP_GREETINGS[randi() % SHOP_GREETINGS.size()]


static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [
		NAME_FIRST[rng.randi_range(0, NAME_FIRST.size() - 1)],
		NAME_LAST[rng.randi_range(0, NAME_LAST.size() - 1)],
	]


static func eulogy() -> String:
	return EULOGIES[randi() % EULOGIES.size()]


static func carl_news() -> String:
	return CARL_NEWS[randi() % CARL_NEWS.size()]


static func box_quip() -> String:
	return BOX_QUIPS[randi() % BOX_QUIPS.size()]


static func welcome(char_name: String) -> String:
	return WELCOME_LINES[randi() % WELCOME_LINES.size()] % char_name
