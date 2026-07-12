class_name EnemyAI
extends RefCounted
## Greedy chase AI — no pathfinding. Attack if orthogonally adjacent, else
## step along the larger-delta axis toward the player, else wander.


static func act(enemy: Entity, dungeon: Dungeon) -> void:
	var def := enemy.enemy_def
	enemy.turn_counter += 1
	if enemy.turn_counter % def.move_every_n_turns != 0:
		return  # slow enemies skip turns

	var ppos: Vector2i = dungeon.player.grid_pos
	var delta := ppos - enemy.grid_pos

	if absi(delta.x) + absi(delta.y) == 1:
		if dungeon.grid.is_safe(ppos):
			return  # player is in a saferoom: lurk hungrily, legally
		_attack_player(enemy, dungeon)
		return

	var cheb := maxi(absi(delta.x), absi(delta.y))
	if cheb <= def.aggro_range:
		var primary: Vector2i
		var secondary: Vector2i
		if absi(delta.x) >= absi(delta.y):
			primary = Vector2i(signi(delta.x), 0)
			secondary = Vector2i(0, signi(delta.y))
		else:
			primary = Vector2i(0, signi(delta.y))
			secondary = Vector2i(signi(delta.x), 0)
		for step in [primary, secondary]:
			if step == Vector2i.ZERO:
				continue
			var target: Vector2i = enemy.grid_pos + step
			if dungeon.grid.is_open(target) and not dungeon.grid.is_safe(target):
				dungeon.grid.move_entity(enemy, enemy.grid_pos, target)
				enemy.set_grid_pos(target)
				return
		return  # both blocked: wait

	# Out of aggro range: occasional random shuffle
	if GameState.rng.randf() < 0.25:
		var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		var step: Vector2i = dirs[GameState.rng.randi_range(0, 3)]
		var target: Vector2i = enemy.grid_pos + step
		if dungeon.grid.is_open(target) and not dungeon.grid.is_safe(target):
			dungeon.grid.move_entity(enemy, enemy.grid_pos, target)
			enemy.set_grid_pos(target)


static func _attack_player(enemy: Entity, dungeon: Dungeon) -> void:
	var c: CharacterData = GameState.character
	enemy.bump_toward(dungeon.player.grid_pos - enemy.grid_pos)
	if Combat.try_dodge(c, GameState.rng):
		Events.msg("You dodge the %s." % enemy.display_name(), &"combat")
		return
	var dmg := Combat.enemy_attack_damage(enemy, GameState.floor_number, c)
	c.hp = maxi(c.hp - dmg, 0)
	Events.msg("%s hits you for %d." % [enemy.display_name(), dmg], &"combat")
	Events.hud_refresh.emit()
