class_name ItemData
extends Resource
## A rolled item instance: base definition + rarity + affixes.

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := ["#b0b0b0", "#4fc14f", "#4f9fe8", "#b45fe8", "#f0a030"]

var base: ItemDef
var rarity := Rarity.COMMON
var affixes: Array = []  # [{ "stat": StringName, "amount": int, "prefix": String }] or suffix
var prefix := ""   # e.g. "Brutal"
var suffix := ""   # e.g. "of the Ox"


func display_name() -> String:
	var parts: Array[String] = []
	if prefix != "":
		parts.append(prefix)
	parts.append(base.display_name)
	if suffix != "":
		parts.append(suffix)
	return " ".join(parts)


func colored_name() -> String:
	return "[color=%s]%s[/color]" % [RARITY_COLORS[rarity], display_name()]


func rarity_name() -> String:
	return RARITY_NAMES[rarity]


func is_consumable() -> bool:
	return base.slot == &"consumable"


## Bonus to a character stat (STR/DEX/CON/INT/CHA) from affixes + innate bonus.
func get_stat_bonus(stat: StringName) -> int:
	var total: int = base.base_bonus.get(stat, 0)
	for affix: Dictionary in affixes:
		if affix["stat"] == stat:
			total += affix["amount"]
	return total


func get_damage() -> int:
	var total := base.damage
	for affix: Dictionary in affixes:
		if affix["stat"] == &"damage":
			total += affix["amount"]
	return total


func get_defense() -> int:
	var total := base.defense
	for affix: Dictionary in affixes:
		if affix["stat"] == &"defense":
			total += affix["amount"]
	return total


## Multi-line tooltip/detail text.
func describe() -> String:
	var lines: Array[String] = []
	lines.append("%s (%s %s)" % [display_name(), rarity_name(), base.slot])
	if base.slot == &"weapon":
		lines.append("Damage: %d" % get_damage())
	elif get_defense() > 0:
		lines.append("Defense: %d" % get_defense())
	for stat in CharacterData.STAT_NAMES:
		var bonus := get_stat_bonus(stat)
		if bonus != 0:
			lines.append("%s %+d" % [stat, bonus])
	if base.flavor_text != "":
		lines.append(base.flavor_text)
	return "\n".join(lines)
