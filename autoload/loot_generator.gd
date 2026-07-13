extends Node
## Rolls items, affixes, and loot boxes. CHA slightly biases rarity —
## the audience likes charming crawlers.

const TIER_NAMES := ["Bronze", "Silver", "Gold", "Platinum"]
const TIER_COLORS := ["#b07040", "#c0c0c8", "#e8c040", "#90e8e0"]

## Suffix affixes add a character stat.
const SUFFIXES := [
	{ "stat": &"STR", "name": "of the Ox" },
	{ "stat": &"DEX", "name": "of the Ferret" },
	{ "stat": &"CON", "name": "of the Tank" },
	{ "stat": &"INT", "name": "of the Nerd" },
	{ "stat": &"CHA", "name": "of the Influencer" },
]

## Prefix names indexed by bonus magnitude (clamped).
const PREFIX_NAMES := ["Fine", "Brutal", "System-Certified", "Apocalyptic"]

var _defs: Array[ItemDef] = []
var _potion_def: ItemDef


func _ready() -> void:
	_defs = ItemDef.all()
	for def in _defs:
		if def.id == &"healing_potion":
			_potion_def = def


func get_def(id: StringName) -> ItemDef:
	for def in _defs:
		if def.id == id:
			return def
	return null


## Box tiers raise the rarity distribution; deeper floors help too.
## (CHA no longer biases loot — it multiplies viewer gains instead; see Fame.)
func roll_rarity(tier: int, floor_num: int) -> int:
	var roll := GameState.rng.randf() + tier * 0.18 + (floor_num - 1) * 0.03
	if roll >= 1.05:
		return ItemData.Rarity.LEGENDARY
	elif roll >= 0.92:
		return ItemData.Rarity.EPIC
	elif roll >= 0.75:
		return ItemData.Rarity.RARE
	elif roll >= 0.5:
		return ItemData.Rarity.UNCOMMON
	return ItemData.Rarity.COMMON


## level_bonus lets fancier sources (gold/platinum boxes) drop above-floor gear.
func roll_item(floor_num: int, rarity: int, level_bonus: int = 0) -> ItemData:
	var pool: Array[ItemDef] = []
	for def in _defs:
		if def.min_floor <= floor_num and def.slot != &"consumable":
			pool.append(def)
	var item := ItemData.new()
	item.base = pool[GameState.rng.randi_range(0, pool.size() - 1)]
	item.rarity = rarity
	item.item_level = maxi(1, floor_num + level_bonus + GameState.rng.randi_range(0, 1))
	_roll_affixes(item)
	return item


func make_potion() -> ItemData:
	var item := ItemData.new()
	item.base = _potion_def
	return item


## Rarity determines affix count: prefix boosts the item's primary stat,
## suffixes add character stats. Magnitudes scale with the item's level.
func _roll_affixes(item: ItemData) -> void:
	var count: int = item.rarity  # COMMON=0 ... LEGENDARY=4
	if count <= 0:
		return
	var rng := GameState.rng
	var ilvl: int = maxi(item.item_level, 1)

	# First affix: primary-stat prefix
	var primary: StringName = &"damage" if item.base.slot == &"weapon" else &"defense"
	var magnitude: int = item.rarity + rng.randi_range(0, 1) + floori((ilvl - 1) / 2.0)
	item.affixes.append({ "stat": primary, "amount": magnitude, "name": "prefix" })
	item.prefix = PREFIX_NAMES[clampi(item.rarity - 1, 0, PREFIX_NAMES.size() - 1)]
	count -= 1

	# Remaining affixes: character-stat suffixes (first one names the item)
	var suffix_pool := SUFFIXES.duplicate()
	suffix_pool.shuffle()
	for i in mini(count, suffix_pool.size()):
		var suffix: Dictionary = suffix_pool[i]
		var amount: int = 1 + rng.randi_range(0, 1) + floori(item.rarity / 2.0) + floori((ilvl - 1) / 4.0)
		item.affixes.append({ "stat": suffix["stat"], "amount": amount, "name": suffix["name"] })
		if item.suffix == "":
			item.suffix = suffix["name"]


## --- Shop economy ---
## Base value of an item; buy/sell prices derive from it, adjusted by CHA.

func price_of(item: ItemData) -> int:
	if item.is_consumable():
		return 15
	var base := 12 + item.get_damage() * 6 + item.get_defense() * 8
	for stat in CharacterData.STAT_NAMES:
		base += item.get_stat_bonus(stat) * 10
	return int(base * (1.0 + item.rarity * 0.5))


func buy_price(item: ItemData, cha: int) -> int:
	var discount := clampi(cha - 8, 0, 10) * 0.02
	return maxi(1, roundi(price_of(item) * (1.0 - discount)))


func sell_price(item: ItemData, cha: int) -> int:
	var bonus := clampi(cha - 8, 0, 10) * 0.01
	return maxi(1, roundi(price_of(item) * (0.35 + bonus)))


## Shop stock: 4 pieces of gear (skewed decent) + 2 potions.
func roll_shop_stock(floor_num: int) -> Array:
	var stock: Array = []
	for i in 4:
		stock.append(roll_item(floor_num, roll_rarity(1 + (i % 2), floor_num)))
	for i in 2:
		stock.append(make_potion())
	return stock


## Opens a box: 1-3 items, tier raises count odds and rarity. ~25% potion slots.
func open_box(tier: int, floor_num: int) -> Array:
	var rng := GameState.rng
	var count := 1 + (1 if rng.randf() < 0.35 + tier * 0.15 else 0) + (1 if rng.randf() < tier * 0.12 else 0)
	var items: Array = []
	for i in count:
		if rng.randf() < 0.25:
			items.append(make_potion())
		else:
			# Gold/platinum boxes drop above-floor item levels
			items.append(roll_item(floor_num, roll_rarity(tier, floor_num), maxi(0, tier - 1)))
	return items
