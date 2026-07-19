class_name EnemyAI
extends RefCounted
## Greedy chase AI — no pathfinding. Attack if orthogonally adjacent, else
## step along the larger-delta axis toward the player, else wander.


static func act(enemy: Entity, dungeon: Dungeon) -> void:
	var def := enemy.enemy_def
	enemy.turn_counter += 1
	if enemy.turn_counter % def.move_every_n_turns != 0:
		return  # slow enemies skip turns

	var target := _nearest_crawler(enemy, dungeon)
	if target == null:
		return
	var ppos: Vector2i = target.grid_pos
	var delta := ppos - enemy.grid_pos

	# A telegraphed strike resolves against the tile it aimed at — move away
	# during the windup and it hits floor. Whichever crawler stands there eats it.
	if enemy.winding_up:
		enemy.winding_up = false
		enemy.set_telegraphing(false)
		enemy.bump_toward(enemy.windup_target - enemy.grid_pos)
		var victim: Object = dungeon.grid.entity_at(enemy.windup_target)
		if victim is Entity and (victim as Entity).is_crawler() \
				and not dungeon.grid.is_safe(enemy.windup_target):
			_attack_crawler(enemy, dungeon, victim as Entity)
		else:
			Events.msg("%s's crushing blow hits empty floor." % enemy.display_name(), &"combat")
		return

	# Ranged enemies: flee when crowded, spit along line of sight, else approach
	if def.ranged:
		var cheb_r := maxi(absi(delta.x), absi(delta.y))
		if dungeon.grid.is_safe(ppos):
			return
		if cheb_r <= 2:
			_step_away(enemy, dungeon, ppos)
			return
		if cheb_r <= def.attack_range and dungeon.grid.has_line_of_sight(enemy.grid_pos, ppos):
			dungeon.show_projectile(enemy.grid_pos, ppos, enemy.color)
			_attack_crawler(enemy, dungeon, target)
			return
		if cheb_r <= def.aggro_range:
			_step_toward(enemy, dungeon, ppos)
		return

	if absi(delta.x) + absi(delta.y) == 1:
		if dungeon.grid.is_safe(ppos):
			return  # player is in a saferoom: lurk hungrily, legally
		if enemy.telegraphs_attacks:
			enemy.winding_up = true
			enemy.windup_target = ppos
			enemy.set_telegraphing(true)
			Events.msg("The %s winds up something enormous..." % enemy.display_name(), &"combat")
			return
		_attack_crawler(enemy, dungeon, target)
		return

	var cheb := maxi(absi(delta.x), absi(delta.y))
	if cheb <= def.aggro_range:
		_step_toward(enemy, dungeon, ppos)
		return

	# Out of aggro range: occasional random shuffle
	if GameState.rng.randf() < 0.25:
		var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		var step: Vector2i = dirs[GameState.rng.randi_range(0, 3)]
		_try_step(enemy, dungeon, step)


## Greedy step along the larger-delta axis toward a target position.
static func _step_toward(enemy: Entity, dungeon: Dungeon, target_pos: Vector2i) -> void:
	var delta := target_pos - enemy.grid_pos
	for step in _axis_steps(delta):
		if _try_step(enemy, dungeon, step):
			return


## Inverse greedy: step to open distance from the target position.
static func _step_away(enemy: Entity, dungeon: Dungeon, target_pos: Vector2i) -> void:
	var delta := enemy.grid_pos - target_pos
	if delta == Vector2i.ZERO:
		delta = Vector2i.RIGHT
	for step in _axis_steps(delta):
		if _try_step(enemy, dungeon, step):
			return


static func _axis_steps(delta: Vector2i) -> Array[Vector2i]:
	var primary: Vector2i
	var secondary: Vector2i
	if absi(delta.x) >= absi(delta.y):
		primary = Vector2i(signi(delta.x), 0)
		secondary = Vector2i(0, signi(delta.y))
	else:
		primary = Vector2i(0, signi(delta.y))
		secondary = Vector2i(signi(delta.x), 0)
	var steps: Array[Vector2i] = []
	if primary != Vector2i.ZERO:
		steps.append(primary)
	if secondary != Vector2i.ZERO:
		steps.append(secondary)
	return steps


static func _try_step(enemy: Entity, dungeon: Dungeon, step: Vector2i) -> bool:
	var target: Vector2i = enemy.grid_pos + step
	if dungeon.grid.is_open(target) and not dungeon.grid.is_safe(target):
		dungeon.grid.move_entity(enemy, enemy.grid_pos, target)
		enemy.set_grid_pos(target)
		return true
	return false


## Legacy wrapper (kept for tests): attack whichever crawler is nearest.
static func _attack_player(enemy: Entity, dungeon: Dungeon) -> void:
	_attack_crawler(enemy, dungeon, _nearest_crawler(enemy, dungeon))


static func _attack_crawler(enemy: Entity, dungeon: Dungeon, target: Entity) -> void:
	if target == null or target.sheet == null:
		return
	var sheet: CharacterData = target.sheet
	enemy.bump_toward(target.grid_pos - enemy.grid_pos)
	if Combat.try_dodge(sheet, GameState.rng):
		if target.is_player:
			Events.msg("You dodge the %s." % enemy.display_name(), &"combat")
		return
	var dmg := Combat.enemy_attack_damage(enemy, GameState.floor_number, sheet)
	if target.is_player:
		Events.msg("%s hits you for %d." % [enemy.display_name(), dmg], &"combat")
	if enemy.enemy_def.poison_chance > 0.0 and sheet.hp - dmg > 0 \
			and GameState.rng.randf() < enemy.enemy_def.poison_chance:
		sheet.statuses[&"poison"] = { "power": 2, "ticks": 4 }
		if target.is_player:
			Events.msg("Venom seeps in. You are POISONED.", &"combat")
	var record: CrawlerRecord = target.crawler_record
	if record == null and target.is_player:
		record = dungeon.turn_manager.player_record()
	if record != null:
		dungeon.turn_manager.damage_crawler(record, dmg, "killed by %s" % enemy.display_name())
	else:
		sheet.hp = maxi(sheet.hp - dmg, 0)


## Enemies hunt whichever instantiated crawler is closest (ties: first in list).
static func _nearest_crawler(enemy: Entity, dungeon: Dungeon) -> Entity:
	var best: Entity = null
	var best_dist := 1 << 30
	for candidate: Entity in dungeon.real_crawler_entities:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var d := maxi(absi(candidate.grid_pos.x - enemy.grid_pos.x),
			absi(candidate.grid_pos.y - enemy.grid_pos.y))
		if d < best_dist:
			best_dist = d
			best = candidate
	return best
