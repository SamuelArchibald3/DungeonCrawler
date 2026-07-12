class_name TurnManager
extends Node
## The game loop. Player input -> player action -> enemy turns -> post-turn
## checks. Synchronous: all state changes are immediate; tweens are cosmetic.

enum State { AWAITING_INPUT, RESOLVING, LOCKED }

var state := State.AWAITING_INPUT
var dungeon: Dungeon
var saferoom_announced := false
var _collapse_safe_notified := false


func _unhandled_input(event: InputEvent) -> void:
	if state != State.AWAITING_INPUT:
		return
	if event.is_action_pressed("move_up", true):
		_do_turn(Vector2i.UP)
	elif event.is_action_pressed("move_down", true):
		_do_turn(Vector2i.DOWN)
	elif event.is_action_pressed("move_left", true):
		_do_turn(Vector2i.LEFT)
	elif event.is_action_pressed("move_right", true):
		_do_turn(Vector2i.RIGHT)
	elif event.is_action_pressed("wait"):
		_do_turn(Vector2i.ZERO)
	elif event.is_action_pressed("ability"):
		_use_ability()


func lock() -> void:
	state = State.LOCKED


func unlock() -> void:
	if state == State.LOCKED:
		state = State.AWAITING_INPUT


func _do_turn(dir: Vector2i) -> void:
	state = State.RESOLVING
	var turn_taken := _resolve_player(dir)
	if turn_taken:
		_resolve_enemies()
		_post_turn()
	if state == State.RESOLVING:
		state = State.AWAITING_INPUT


## Returns true if the action consumed a turn.
func _resolve_player(dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return true  # wait

	var player := dungeon.player
	var target := player.grid_pos + dir
	var occupant: Object = dungeon.grid.entity_at(target)

	if occupant is Entity and (occupant as Entity).enemy_def != null:
		_player_attack(occupant as Entity, dir)
		return true

	if occupant != null and occupant.has_method("on_bumped"):
		occupant.on_bumped()
		return true

	if not dungeon.grid.is_walkable(target):
		return false  # bumped a wall: no turn consumed

	dungeon.grid.move_entity(player, player.grid_pos, target)
	player.set_grid_pos(target)

	if dungeon.grid.is_safe(target) and not saferoom_announced:
		saferoom_announced = true
		Events.msg("You enter a System-certified Safe Room™. Monsters legally cannot follow. Probably.", &"system")

	var zone := dungeon.zone_at(target)
	if zone != -1 and not dungeon.zone_visited.has(zone):
		dungeon.zone_visited[zone] = true
		Events.msg("Now entering %s. Population: hostile." % dungeon.zone_name(zone), &"system")

	if dungeon.grid.get_tile(target) == DungeonGrid.STAIRS:
		state = State.LOCKED
		dungeon.descend_requested.emit()
		return false
	return true


func _player_attack(enemy: Entity, dir: Vector2i) -> void:
	var c: CharacterData = GameState.character
	var dmg := Combat.player_attack_damage(c, enemy, GameState.rng)
	enemy.hp -= dmg
	dungeon.player.bump_toward(dir)
	if enemy.hp <= 0:
		Events.msg("You hit the %s for %d, killing it." % [enemy.display_name(), dmg], &"combat")
		_kill_enemy(enemy)
	else:
		Events.msg("You hit the %s for %d." % [enemy.display_name(), dmg], &"combat")


func _kill_enemy(enemy: Entity) -> void:
	var c: CharacterData = GameState.character
	GameState.kills += 1
	dungeon.grid.remove_entity(enemy.grid_pos)
	dungeon.enemies.erase(enemy)

	if enemy.is_boss:
		Events.msg("NEIGHBOURHOOD BOSS DEFEATED: %s. The locals do not send their regards." % enemy.boss_name, &"system")
		dungeon.spawn_loot_box(2, enemy.grid_pos)  # guaranteed gold box
		if enemy.zone_index != -1:
			dungeon.reveal_zone(enemy.zone_index)
			Events.msg("District survey data unlocked: %s added to your map." % dungeon.zone_name(enemy.zone_index), &"system")
	elif GameState.rng.randf() < enemy.enemy_def.drop_chance:
		dungeon.spawn_loot_box(0, enemy.grid_pos)  # bronze box drop

	var gold := 1 + GameState.rng.randi_range(0, 2) + floori(enemy.xp_value / 3.0)
	c.gold += gold
	Events.msg("+%d gold." % gold, &"loot")
	Events.enemy_killed.emit(enemy.enemy_def.id, enemy.is_boss)
	if enemy.is_boss and _all_bosses_dead():
		Events.all_bosses_cleared.emit()
		Events.msg("ALL NEIGHBOURHOOD BOSSES DEFEATED. The floor's org chart is now a suggestion.", &"system")

	if c.gain_xp(enemy.xp_value):
		Events.msg("LEVEL UP! You are now level %d. The System is mildly impressed." % c.level, &"system")
		Events.level_up.emit(c.level)
	enemy.queue_free()
	Events.hud_refresh.emit()


func _all_bosses_dead() -> bool:
	for info: Dictionary in dungeon.zones_runtime:
		var boss: Variant = info["boss"]
		if boss != null and is_instance_valid(boss) and boss.hp > 0:
			return false
	return true


func _resolve_enemies() -> void:
	for enemy in dungeon.enemies.duplicate():
		if enemy.hp <= 0:
			continue
		EnemyAI.act(enemy, dungeon)
		if GameState.character.hp <= 0:
			state = State.LOCKED
			Events.player_died.emit()
			return


func _post_turn() -> void:
	var c: CharacterData = GameState.character
	# Tick active-ability cooldowns
	for id in c.ability_cooldowns.keys():
		c.ability_cooldowns[id] = maxi(c.ability_cooldowns[id] - 1, 0)
	# Saferoom regen
	if dungeon.grid.is_safe(dungeon.player.grid_pos) and c.hp > 0:
		c.heal(2)
	dungeon.reveal_around(dungeon.player.grid_pos)
	_tick_floor_timer(c)
	Events.hud_refresh.emit()


func _tick_floor_timer(c: CharacterData) -> void:
	if GameState.floor_turns_left > 0:
		GameState.floor_turns_left -= 1
		match GameState.floor_turns_left:
			100:
				Events.msg("REMINDER: This floor closes in 100 turns. The System suggests you stop sightseeing.", &"system")
			50:
				Events.msg("WARNING: 50 turns until floor collapse. Descending is not mandatory, but neither is survival.", &"system")
			25:
				Events.msg("URGENT: 25 turns remaining. Your life insurance does not cover 'floor'.", &"system")
			0:
				Events.msg("THE FLOOR IS NOW CLOSED. Thank you for your participation. The ceiling will assist you shortly.", &"system")
			_:
				if GameState.floor_turns_left < 10:
					Events.msg("Floor collapse in %d..." % GameState.floor_turns_left, &"system")
		return

	# Floor is collapsed — but saferooms honor their warranty
	if dungeon.grid.is_safe(dungeon.player.grid_pos):
		if not _collapse_safe_notified:
			_collapse_safe_notified = true
			Events.msg("The floor collapses around the Safe Room. The System honors its warranty, begrudgingly.", &"system")
		return

	# Escalating damage every turn until descent or death
	GameState.collapse_ticks += 1
	var dmg: int = 5 * GameState.collapse_ticks
	c.hp = maxi(c.hp - dmg, 0)
	Events.msg("The ceiling grinds downward. You take %d crush damage." % dmg, &"combat")
	if c.hp <= 0:
		Events.msg("The floor claims another tenant.", &"system")
		state = State.LOCKED
		Events.player_died.emit()
	else:
		Events.crush_survived.emit()


## Race/class selection fires on arriving at floor 3, once per run.
func maybe_trigger_race_class() -> void:
	if GameState.floor_number >= 3 and not GameState.race_class_done:
		state = State.LOCKED
		dungeon.race_class_requested.emit()


func _use_ability() -> void:
	var c: CharacterData = GameState.character
	var active := Abilities.first_active(c)
	if active == &"":
		Events.msg("No active ability. Try surviving to level 3 first.", &"system")
		return
	if c.ability_cooldowns.get(active, 0) > 0:
		Events.msg("%s is on cooldown (%d turns)." % [Abilities.display_name(active), c.ability_cooldowns[active]], &"system")
		return
	state = State.RESOLVING
	var used: bool = Abilities.use_active(active, dungeon)
	if used:
		c.ability_cooldowns[active] = Abilities.cooldown(active)
		_resolve_enemies()
		_post_turn()
	if state == State.RESOLVING:
		state = State.AWAITING_INPUT
