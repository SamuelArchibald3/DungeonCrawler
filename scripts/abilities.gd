class_name Abilities
extends RefCounted
## Small fixed ability pool, reused across race/class defs. Two shapes only:
## passives (checked inline in combat.gd) and actives (hotkey Q, turn CDs).

const DATA := {
	&"thick_skin": {
		"name": "Thick Skin", "kind": "passive", "cd": 0,
		"desc": "Take 1 less damage from every hit.",
	},
	&"backstab": {
		"name": "Backstab", "kind": "passive", "cd": 0,
		"desc": "+50% damage against enemies at full health.",
	},
	&"power_slam": {
		"name": "Power Slam", "kind": "active", "cd": 6,
		"desc": "Q: Damage all adjacent enemies (scales with INT).",
	},
	&"smoke_step": {
		"name": "Smoke Step", "kind": "active", "cd": 8,
		"desc": "Q: Teleport to a nearby open tile.",
	},
	&"heal_pulse": {
		"name": "Heal Pulse", "kind": "active", "cd": 10,
		"desc": "Q: Heal 25% of max HP (scales with INT).",
	},
}


static func display_name(id: StringName) -> String:
	return DATA[id]["name"] if DATA.has(id) else String(id)


static func description(id: StringName) -> String:
	return DATA[id]["desc"] if DATA.has(id) else ""


static func cooldown(id: StringName) -> int:
	return DATA[id]["cd"] if DATA.has(id) else 0


static func is_active(id: StringName) -> bool:
	return DATA.has(id) and DATA[id]["kind"] == "active"


## The character's first active ability (the one bound to Q), or &"".
static func first_active(c: CharacterData) -> StringName:
	for id in c.abilities:
		if is_active(id):
			return id
	return &""


## Executes an active ability. Returns false if it fizzled (no turn consumed).
static func use_active(id: StringName, dungeon: Dungeon) -> bool:
	var c: CharacterData = GameState.character
	var player := dungeon.player
	match id:
		&"power_slam":
			var dmg := 5 + maxi(c.get_stat(&"INT") - 8, 0)
			var hit_any := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var target: Object = dungeon.grid.entity_at(player.grid_pos + Vector2i(dx, dy))
					if target is Entity and (target as Entity).enemy_def != null:
						var enemy := target as Entity
						enemy.hp -= dmg
						hit_any = true
						if enemy.hp <= 0:
							Events.msg("POWER SLAM crushes the %s for %d!" % [enemy.display_name(), dmg], &"combat")
							dungeon.turn_manager._kill_enemy(enemy)
						else:
							Events.msg("POWER SLAM hits the %s for %d." % [enemy.display_name(), dmg], &"combat")
			if not hit_any:
				Events.msg("You slam the ground dramatically. Nothing is nearby. The viewers cringe.", &"combat")
			return true
		&"smoke_step":
			var candidates: Array[Vector2i] = []
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var p := player.grid_pos + Vector2i(dx, dy)
					var dist := maxi(absi(dx), absi(dy))
					if dist >= 2 and dungeon.grid.is_open(p) and dungeon.grid.get_tile(p) == DungeonGrid.FLOOR:
						candidates.append(p)
			if candidates.is_empty():
				Events.msg("No room to smoke-step. Awkward.", &"system")
				return false
			var dest: Vector2i = candidates[GameState.rng.randi_range(0, candidates.size() - 1)]
			dungeon.grid.move_entity(player, player.grid_pos, dest)
			player.set_grid_pos(dest, false)
			Events.msg("You vanish in a puff of vape-flavored smoke.", &"combat")
			return true
		&"heal_pulse":
			if c.hp >= c.max_hp:
				Events.msg("You're already at full health. The System suggests gratitude.", &"system")
				return false
			var amount := floori(c.max_hp * 0.25) + maxi(c.get_stat(&"INT") - 8, 0)
			c.heal(amount)
			Events.msg("HEAL PULSE restores %d HP." % amount, &"combat")
			Events.hud_refresh.emit()
			return true
	return false
