class_name Combat
extends RefCounted
## Pure damage math. Passive abilities hook in here via has_ability checks.


static func player_attack_damage(c: CharacterData, enemy: Entity, rng: RandomNumberGenerator) -> int:
	var dmg := c.get_weapon_damage() + floori((c.get_stat(&"STR") - 8) / 2.0) + rng.randi_range(0, 2)
	if c.has_ability(&"backstab") and enemy.hp == enemy.max_hp:
		dmg = floori(dmg * 1.5)
	dmg -= enemy.enemy_def.defense
	return maxi(dmg, 1)


static func enemy_attack_damage(enemy: Entity, floor_num: int, c: CharacterData) -> int:
	var dmg := enemy.enemy_def.attack + (floor_num - 1) - c.get_defense()
	if enemy.is_borough:
		dmg += 4
	elif enemy.is_boss:
		dmg += 2
	if c.has_ability(&"thick_skin"):
		dmg -= 1
	return maxi(dmg, 1)


## DEX grants (DEX-8)*2% dodge, capped at 30%.
static func try_dodge(c: CharacterData, rng: RandomNumberGenerator) -> bool:
	var chance := clampi((c.get_stat(&"DEX") - 8) * 2, 0, 30)
	return rng.randi_range(1, 100) <= chance
