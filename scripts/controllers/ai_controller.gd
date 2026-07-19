class_name AIController
extends CrawlerController
## Real-tier NPC crawler behavior: fight what's adjacent, act on your
## disposition, loot what's near, otherwise wander the room graph.

const ENEMY_SCAN_RADIUS := 8
const CRAWLER_SCAN_RADIUS := 6
const BOX_SCAN_RADIUS := 5
const FLEE_HP_FRACTION := 0.35


func think(cr: CrawlerRecord, dungeon: Dungeon, tm: TurnManager) -> void:
	var body := cr.entity
	if body == null or not is_instance_valid(body) or not cr.alive:
		return
	cr.pos = body.grid_pos
	var sheet := cr.sheet
	cr.goal_data["emote_cd"] = maxi(int(cr.goal_data.get("emote_cd", 0)) - 1, 0)

	# Hurt: run from the nearest threat
	if sheet.hp < sheet.max_hp * FLEE_HP_FRACTION:
		var threat := _nearest_enemy(dungeon, body, ENEMY_SCAN_RADIUS)
		if threat != null:
			_step_along(tm, cr, body.grid_pos - threat.grid_pos)
			return

	# Something's biting: hit it back
	var foe := _adjacent_enemy(dungeon, body)
	if foe != null:
		body.set_facing(_dir_to(body.grid_pos, foe.grid_pos))
		tm.crawler_attack(cr)
		return

	match cr.disposition:
		CrawlerRecord.Disposition.HOSTILE:
			var prey := _nearest_other_crawler(dungeon, body, CRAWLER_SCAN_RADIUS)
			if prey != null:
				if _chebyshev(body.grid_pos, prey.grid_pos) == 1:
					body.set_facing(_dir_to(body.grid_pos, prey.grid_pos))
					tm.crawler_attack(cr)
				else:
					_step_along(tm, cr, prey.grid_pos - body.grid_pos)
				return
		CrawlerRecord.Disposition.WARY:
			var neighbor := _nearest_other_crawler(dungeon, body, 3)
			if neighbor != null:
				_step_along(tm, cr, body.grid_pos - neighbor.grid_pos)
				return
		CrawlerRecord.Disposition.FRIENDLY:
			var pdist := _chebyshev(body.grid_pos, dungeon.player.grid_pos)
			if pdist > 2 and pdist <= CRAWLER_SCAN_RADIUS:
				_step_along(tm, cr, dungeon.player.grid_pos - body.grid_pos)
				return
			if pdist <= 2 and cr.goal_data["emote_cd"] == 0:
				cr.goal_data["emote_cd"] = 40
				Events.crawler_event.emit(&"emote", cr, {})
				return

	# Loot anything shiny nearby
	var box := _nearest_box(dungeon, body, BOX_SCAN_RADIUS)
	if box != null:
		if absi(box.grid_pos.x - body.grid_pos.x) + absi(box.grid_pos.y - body.grid_pos.y) == 1:
			box.open_for_npc(cr)
		else:
			_step_along(tm, cr, box.grid_pos - body.grid_pos)
		return

	_explore(tm, cr, dungeon)


func _explore(tm: TurnManager, cr: CrawlerRecord, dungeon: Dungeon) -> void:
	var fd := dungeon.floor_data
	var body := cr.entity
	var waypoint: Vector2i = cr.goal_data.get("waypoint", Vector2i(-1, -1))
	if waypoint == Vector2i(-1, -1) or _chebyshev(body.grid_pos, waypoint) <= 1 \
			or int(cr.goal_data.get("stuck", 0)) >= 3:
		var current_room: int = fd.room_of.get(body.grid_pos, cr.room)
		var neighbors: Array = fd.room_graph.get(current_room, [])
		if neighbors.is_empty():
			return
		var next_room: int = neighbors[GameState.rng.randi_range(0, neighbors.size() - 1)]
		waypoint = fd.rooms[next_room].get_center()
		cr.goal_data["waypoint"] = waypoint
		cr.goal_data["stuck"] = 0
	if not _step_along(tm, cr, waypoint - body.grid_pos):
		cr.goal_data["stuck"] = int(cr.goal_data.get("stuck", 0)) + 1


## Greedy step along the larger axis first; returns true if a move landed.
func _step_along(tm: TurnManager, cr: CrawlerRecord, delta: Vector2i) -> bool:
	for step in EnemyAI._axis_steps(delta):
		if tm.crawler_move(cr, step):
			return true
	return false


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _dir_to(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta := to - from
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))


func _nearest_enemy(dungeon: Dungeon, body: Entity, radius: int) -> Entity:
	var best: Entity = null
	var best_dist := radius + 1
	for enemy: Entity in dungeon.enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		var d := _chebyshev(body.grid_pos, enemy.grid_pos)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


func _adjacent_enemy(dungeon: Dungeon, body: Entity) -> Entity:
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var occupant: Object = dungeon.grid.entity_at(body.grid_pos + dir)
		if occupant is Entity and (occupant as Entity).enemy_def != null:
			return occupant as Entity
	return null


func _nearest_other_crawler(dungeon: Dungeon, body: Entity, radius: int) -> Entity:
	var best: Entity = null
	var best_dist := radius + 1
	for candidate: Entity in dungeon.real_crawler_entities:
		if candidate == null or not is_instance_valid(candidate) or candidate == body:
			continue
		var d := _chebyshev(body.grid_pos, candidate.grid_pos)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best


func _nearest_box(dungeon: Dungeon, body: Entity, radius: int) -> LootBox:
	var best: LootBox = null
	var best_dist := radius + 1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var occupant: Object = dungeon.grid.entity_at(body.grid_pos + Vector2i(dx, dy))
			if occupant is LootBox:
				var d := maxi(absi(dx), absi(dy))
				if d < best_dist:
					best_dist = d
					best = occupant as LootBox
	return best
