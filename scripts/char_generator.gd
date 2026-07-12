class_name CharGenerator
extends RefCounted
## Rolls random crawlers for the character creation screen.


## 3d6 per stat, clamped 6..16.
static func roll_stats(rng: RandomNumberGenerator) -> Dictionary:
	var stats := {}
	for stat in CharacterData.STAT_NAMES:
		var roll := rng.randi_range(1, 6) + rng.randi_range(1, 6) + rng.randi_range(1, 6)
		stats[stat] = clampi(roll, 6, 16)
	return stats


static func random_character() -> CharacterData:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var c := CharacterData.new()
	c.char_name = Flavor.random_name(rng)
	c.base_stats = roll_stats(rng)
	c.recompute_max_hp()
	c.hp = c.max_hp
	return c
