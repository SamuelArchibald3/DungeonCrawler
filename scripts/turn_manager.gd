class_name TurnManager
extends Node
## The game loop. Player input -> player action -> enemy turns -> post-turn
## checks. Synchronous: all state changes are immediate; tweens are cosmetic.

enum State { AWAITING_INPUT, RESOLVING, LOCKED }

## Ticked real-time pacing (GameState.realtime_mode): the world resolves a
## "turn" every WORLD_TICK_SECONDS whether or not the player acts, and the
## player may act once per PLAYER_ACTION_SECONDS via held keys.
const WORLD_TICK_SECONDS := 0.45
const PLAYER_ACTION_SECONDS := 0.28
## Entities beyond this Chebyshev distance from the player lie dormant
const ACTIVE_RADIUS := 22

const DIRECTION_ACTIONS := {
	"move_up": Vector2i.UP,
	"move_down": Vector2i.DOWN,
	"move_left": Vector2i.LEFT,
	"move_right": Vector2i.RIGHT,
}

var state := State.AWAITING_INPUT
var dungeon: Dungeon
var saferoom_announced := false
var _collapse_safe_notified := false
var _player_cooldown := 0.0
var _world_accum := 0.0
var _player_rec: CrawlerRecord

## Distance beyond which a real crawler folds back to abstract (hysteresis
## against ACTIVE_RADIUS so promotion/demotion doesn't thrash at the edge).
const DEMOTE_RADIUS := 27

var _sim_ctx := {}
var _sim_floor := -1
var _world_tick_count := 0

## Spectating: the player has descended and is frozen in the waiting room
## while the floor plays out at accelerated speed.
const SPECTATE_MULT := 12
var spectate := false


## The player's roster record (roster[0] when the cohort exists; a local
## mint keeps headless script-mode tests working without autoload state).
func player_record() -> CrawlerRecord:
	if Crawlers.roster.size() > 0:
		_player_rec = Crawlers.roster[0]
	elif _player_rec == null:
		_player_rec = CrawlerRecord.make(0, GameState.character)
		_player_rec.is_player = true
		_player_rec.tier = CrawlerRecord.Tier.REAL
	_player_rec.entity = dungeon.player
	if dungeon.player != null:
		dungeon.player.crawler_record = _player_rec
	return _player_rec


## Real-time pacing: player acts on held keys with a cooldown; the world
## ticks on its own clock. Combat/resolution logic is shared with the
## turn-based path — only the scheduling differs.
func _process(delta: float) -> void:
	if spectate:
		return  # the waiting room drives the accelerated floor via spectate_step
	if not GameState.realtime_mode:
		return
	if state != State.AWAITING_INPUT:
		return  # modals, death, and descent pause the world

	_player_cooldown = maxf(_player_cooldown - delta, 0.0)
	if _player_cooldown <= 0.0:
		if Input.is_action_pressed("attack"):
			_realtime_attack()
		else:
			var dir := _held_direction()
			if dir != Vector2i.ZERO:
				_realtime_player_action(dir)
			elif Input.is_action_just_pressed("ability"):
				_realtime_ability()

	_world_accum += delta
	if _world_accum >= WORLD_TICK_SECONDS:
		_world_accum -= WORLD_TICK_SECONDS
		state = State.RESOLVING
		_resolve_enemies()
		if state == State.RESOLVING:
			_post_turn()
		if state == State.RESOLVING:
			state = State.AWAITING_INPUT


func _held_direction() -> Vector2i:
	for action: String in DIRECTION_ACTIONS:
		if Input.is_action_pressed(action):
			return DIRECTION_ACTIONS[action]
	return Vector2i.ZERO


func _realtime_player_action(dir: Vector2i) -> void:
	state = State.RESOLVING
	var acted := _resolve_player(dir)
	if acted:
		_player_cooldown = PLAYER_ACTION_SECONDS
		Events.hud_refresh.emit()
	if state == State.RESOLVING:
		state = State.AWAITING_INPUT


func _realtime_attack() -> void:
	state = State.RESOLVING
	_resolve_attack()
	_player_cooldown = PLAYER_ACTION_SECONDS
	if state == State.RESOLVING:
		state = State.AWAITING_INPUT


func _realtime_ability() -> void:
	var c: CharacterData = GameState.character
	var active := Abilities.first_active(c)
	if active == &"":
		Events.msg("No active ability. Try surviving to floor 3 first.", &"system")
		return
	if c.ability_cooldowns.get(active, 0) > 0:
		Events.msg("%s is on cooldown (%d ticks)." % [Abilities.display_name(active), c.ability_cooldowns[active]], &"system")
		return
	state = State.RESOLVING
	var used: bool = Abilities.use_active(active, dungeon)
	if used:
		c.ability_cooldowns[active] = Abilities.cooldown(active)
		_player_cooldown = PLAYER_ACTION_SECONDS
		Events.hud_refresh.emit()
	if state == State.RESOLVING:
		state = State.AWAITING_INPUT


func _unhandled_input(event: InputEvent) -> void:
	if GameState.realtime_mode:
		return  # real-time input is polled in _process
	if spectate:
		return  # frozen in the waiting room
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
	elif event.is_action_pressed("attack"):
		state = State.RESOLVING
		_resolve_attack()
		_resolve_enemies()
		if state == State.RESOLVING:
			_post_turn()
		if state == State.RESOLVING:
			state = State.AWAITING_INPUT
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


## Legacy wrappers: the pre-cohort single-player API, bound to roster[0].
func _resolve_attack() -> bool:
	return crawler_attack(player_record())


func _resolve_player(dir: Vector2i) -> bool:
	return crawler_move(player_record(), dir)


## Attack the tile the crawler is facing. Always consumes the action —
## whiffing dramatically is part of the show.
func crawler_attack(cr: CrawlerRecord) -> bool:
	var body := cr.entity
	var target := body.grid_pos + body.facing
	body.play_attack_slash(body.facing)
	var occupant: Object = dungeon.grid.entity_at(target)
	if occupant is Entity and (occupant as Entity).enemy_def != null:
		melee_hit(cr, occupant as Entity, body.facing)
	elif occupant is Entity and (occupant as Entity).is_crawler():
		pvp_hit(cr, occupant as Entity, body.facing)
	elif cr.is_player and occupant != null and occupant.has_method("on_bumped"):
		occupant.on_bumped()  # smashing a box open counts as opening it
	return true


## Returns true if the action consumed a turn.
func crawler_move(cr: CrawlerRecord, dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return true  # wait

	var body := cr.entity
	body.set_facing(dir)
	var target := body.grid_pos + dir
	var occupant: Object = dungeon.grid.entity_at(target)

	if occupant is Entity and ((occupant as Entity).enemy_def != null or (occupant as Entity).is_crawler()):
		return false  # blocked: attacks are a button, not a shoulder-check

	if occupant != null and occupant.has_method("on_bumped"):
		if cr.is_player:
			occupant.on_bumped()
			return true
		return false  # NPC interactions with boxes/NPCs arrive in later milestones

	if not dungeon.grid.is_walkable(target):
		return false  # bumped a wall: no turn consumed

	dungeon.grid.move_entity(body, body.grid_pos, target)
	body.set_grid_pos(target)

	if cr.is_player:
		if dungeon.grid.is_safe(target) and not saferoom_announced:
			saferoom_announced = true
			Events.msg("You enter a System-certified Safe Room™. Monsters legally cannot follow. Probably.", &"system")
		var zone := dungeon.zone_at(target)
		if zone != -1 and not dungeon.zone_visited.has(zone):
			dungeon.zone_visited[zone] = true
			Events.msg("Now entering %s. Population: hostile." % dungeon.zone_name(zone), &"system")

	if dungeon.grid.get_tile(target) == DungeonGrid.STAIRS:
		if cr.is_player:
			state = State.LOCKED
			dungeon.descend_requested.emit()
			return false
		# NPC descent lands with the floor-lifecycle milestone
	return true


func _player_attack(enemy: Entity, dir: Vector2i) -> void:
	melee_hit(player_record(), enemy, dir)


## A crawler's melee strike against a monster.
func melee_hit(cr: CrawlerRecord, enemy: Entity, dir: Vector2i) -> void:
	var dmg := Combat.player_attack_damage(cr.sheet, enemy, GameState.rng)
	enemy.hp -= dmg
	enemy.flash_hit()
	if enemy.hp <= 0:
		if cr.is_player:
			Events.msg("You hit the %s for %d, killing it." % [enemy.display_name(), dmg], &"combat")
		kill_enemy(enemy, cr)
	else:
		if cr.is_player:
			Events.msg("You hit the %s for %d." % [enemy.display_name(), dmg], &"combat")
		_apply_knockback(enemy, dir)


## Crawler-vs-crawler melee (PvP). Messages only when the player is involved.
func pvp_hit(cr: CrawlerRecord, victim_body: Entity, dir: Vector2i) -> void:
	var victim: CrawlerRecord = victim_body.crawler_record
	if victim == null and victim_body.is_player:
		victim = player_record()
	if victim == null:
		return
	var dmg := Combat.crawler_vs_crawler_damage(cr.sheet, victim.sheet, GameState.rng)
	victim_body.bump_toward(Vector2i.ZERO - dir)
	if cr.is_player or victim.is_player:
		Events.msg("%s hits %s for %d." % [cr.sheet.char_name, victim.sheet.char_name, dmg], &"combat")
	damage_crawler(victim, dmg, "slain by %s" % cr.sheet.char_name, cr)
	# Survivors get shoved like anyone else
	if victim.alive and victim.entity != null and is_instance_valid(victim.entity):
		var push := victim.entity.grid_pos + dir
		if dungeon.grid.is_open(push) and not dungeon.grid.is_safe(push):
			dungeon.grid.move_entity(victim.entity, victim.entity.grid_pos, push)
			victim.entity.set_grid_pos(push)


## Single choke point for damage to any crawler, player or NPC.
func damage_crawler(cr: CrawlerRecord, amount: int, _cause: String, killer: CrawlerRecord = null) -> void:
	cr.sheet.hp = maxi(cr.sheet.hp - amount, 0)
	if cr.entity != null and is_instance_valid(cr.entity):
		cr.entity.flash_hit()
	if cr.is_player:
		Events.hud_refresh.emit()
	if cr.entity != null and is_instance_valid(cr.entity) and not cr.is_player:
		cr.entity.max_hp = cr.sheet.max_hp
		cr.entity.hp = cr.sheet.hp  # mirror to the body's health bar
	if cr.sheet.hp <= 0 and cr.alive:
		if cr.is_player:
			state = State.LOCKED
			Events.player_died.emit()
		else:
			Crawlers.kill(cr, _cause, killer)
			if cr.entity != null and is_instance_valid(cr.entity):
				dungeon.grid.remove_entity(cr.entity.grid_pos)
				dungeon.real_crawler_entities.erase(cr.entity)
				cr.entity.queue_free()
			cr.entity = null
			cr.controller = null


## Hits shove smaller enemies back a tile; wall slams hurt. Heavies stand
## firm — unless caught mid-windup, when a shove interrupts the telegraph.
func _apply_knockback(enemy: Entity, dir: Vector2i) -> void:
	if (enemy.is_boss or enemy.telegraphs_attacks) and not enemy.winding_up:
		return
	var push := enemy.grid_pos + dir
	if dungeon.grid.is_open(push) and not dungeon.grid.is_safe(push):
		dungeon.grid.move_entity(enemy, enemy.grid_pos, push)
		enemy.set_grid_pos(push)
		if enemy.winding_up:
			enemy.winding_up = false
			enemy.set_telegraphing(false)
			Events.msg("The shove interrupts %s's windup." % enemy.display_name(), &"combat")
	else:
		var slam := 3
		enemy.hp -= slam
		enemy.flash_hit()
		if enemy.hp <= 0:
			Events.msg("%s slams into the wall for %d." % [enemy.display_name(), slam], &"combat")
			_kill_enemy(enemy)
		else:
			enemy.statuses[&"stun"] = 2
			enemy.set_stun_visual(true)
			Events.msg("%s slams into the wall for %d and is STUNNED." % [enemy.display_name(), slam], &"combat")


func _kill_enemy(enemy: Entity) -> void:
	kill_enemy(enemy, player_record())


## Any crawler killing a monster. Floor-wide effects (stairs unlock, box
## drops) happen for every killer; player-attributed signals, map reveals,
## and log messages only fire for roster[0].
func kill_enemy(enemy: Entity, killer: CrawlerRecord) -> void:
	if killer.is_player:
		GameState.kills += 1
	dungeon.grid.remove_entity(enemy.grid_pos)
	dungeon.enemies.erase(enemy)

	if enemy.is_borough:
		dungeon.unlock_stairs()
		dungeon.spawn_loot_box(3, enemy.grid_pos)  # guaranteed platinum box
		if killer.is_player:
			Events.msg("BOROUGH BOSS DEFEATED: %s. The stairwell is under new management. Yours." % enemy.boss_name, &"system")
			Events.msg("The sealed stairwell grinds open. Express route: unlocked.", &"system")
			dungeon.reveal_all()
			Events.msg("Full borough survey unlocked. The map is yours.", &"system")
			Events.borough_boss_killed.emit()
	elif enemy.is_boss:
		dungeon.spawn_loot_box(2, enemy.grid_pos)  # guaranteed gold box
		if killer.is_player:
			Events.msg("NEIGHBOURHOOD BOSS DEFEATED: %s. The locals do not send their regards." % enemy.boss_name, &"system")
			if enemy.zone_index != -1:
				dungeon.reveal_zone(enemy.zone_index)
				Events.msg("District survey data unlocked: %s added to your map." % dungeon.zone_name(enemy.zone_index), &"system")
	elif GameState.rng.randf() < enemy.enemy_def.drop_chance:
		dungeon.spawn_loot_box(0, enemy.grid_pos)  # bronze box drop

	var gold := 1 + GameState.rng.randi_range(0, 2) + floori(enemy.xp_value / 3.0)
	killer.sheet.gold += gold
	killer.kills += 1
	if killer.is_player:
		Events.msg("+%d gold." % gold, &"loot")
		Events.enemy_killed.emit(enemy.enemy_def.id, enemy.is_boss)
		if enemy.is_boss and _all_bosses_dead():
			Events.all_bosses_cleared.emit()
			Events.msg("ALL NEIGHBOURHOOD BOSSES DEFEATED. The floor's org chart is now a suggestion.", &"system")

	if killer.sheet.gain_xp(enemy.xp_value) and killer.is_player:
		Events.msg("LEVEL UP! You are now level %d. The System is mildly impressed." % killer.sheet.level, &"system")
		Events.level_up.emit(killer.sheet.level)
	enemy.queue_free()
	if killer.is_player:
		Events.hud_refresh.emit()


func _all_bosses_dead() -> bool:
	for info: Dictionary in dungeon.zones_runtime:
		var boss: Variant = info["boss"]
		if boss != null and is_instance_valid(boss) and boss.hp > 0:
			return false
	return true


func _resolve_enemies() -> void:
	var ppos: Vector2i = dungeon.player.grid_pos
	for enemy in dungeon.enemies.duplicate():
		if enemy.hp <= 0:
			continue
		if maxi(absi(enemy.grid_pos.x - ppos.x), absi(enemy.grid_pos.y - ppos.y)) > ACTIVE_RADIUS:
			continue  # dormant beyond the activity bubble
		if enemy.statuses.get(&"stun", 0) > 0:
			enemy.statuses[&"stun"] -= 1
			if enemy.statuses[&"stun"] <= 0:
				enemy.statuses.erase(&"stun")
				enemy.set_stun_visual(false)
			continue  # seeing stars: no action this tick
		EnemyAI.act(enemy, dungeon)
		if state == State.LOCKED:
			return  # a death (the player's) halted the world


## Real-tier NPC crawlers take their actions alongside the world tick.
func _resolve_crawlers() -> void:
	for cr in Crawlers.real_records():
		if cr.is_player or not cr.alive or cr.controller == null:
			continue
		cr.controller.think(cr, dungeon, self)
		if state == State.LOCKED:
			return


## Advance the distant cohort: retier crawlers around the player, then run
## staggered abstract macro-steps for those still out of the bubble.
func _advance_cohort() -> void:
	if Crawlers.roster.size() <= 1:
		return
	_world_tick_count += 1
	_update_tiers()
	_ensure_sim_ctx()
	_sim_ctx["turns_left"] = GameState.floor_turns_left
	for cr in Crawlers.npc_records():
		if not cr.alive or cr.descended or cr.tier == CrawlerRecord.Tier.REAL:
			continue
		if (_world_tick_count + cr.id) % CrawlerSim.SIM_PERIOD != 0:
			continue
		for ev in CrawlerSim.macro_step(cr, _sim_ctx):
			_apply_sim_event(ev)


## Promote abstract crawlers that wander into the bubble; demote real ones
## that leave it.
func _update_tiers() -> void:
	if spectate or dungeon.player == null or not is_instance_valid(dungeon.player):
		return  # no player anchor while spectating: everyone stays abstract
	var ppos: Vector2i = dungeon.player.grid_pos
	for cr in Crawlers.npc_records():
		if not cr.alive or cr.descended:
			continue
		if cr.tier == CrawlerRecord.Tier.REAL:
			if cr.entity == null or not is_instance_valid(cr.entity):
				continue
			var d := maxi(absi(cr.entity.grid_pos.x - ppos.x), absi(cr.entity.grid_pos.y - ppos.y))
			if d > DEMOTE_RADIUS:
				dungeon.demote_crawler(cr)
		else:
			var d := maxi(absi(cr.pos.x - ppos.x), absi(cr.pos.y - ppos.y))
			if d <= ACTIVE_RADIUS:
				dungeon.promote_crawler(cr)


func _ensure_sim_ctx() -> void:
	if _sim_floor == GameState.floor_number and not _sim_ctx.is_empty():
		return
	_sim_ctx = CrawlerSim.build_context(dungeon.floor_data, GameState.floor_number,
		GameState.sim_rng, Crawlers.roster, GameState.floor_turns_left)
	_sim_floor = GameState.floor_number


func _apply_sim_event(ev: Dictionary) -> void:
	match ev["kind"]:
		&"died":
			Crawlers.kill(ev["cr"], ev.get("cause", "the dungeon"))
		&"descended":
			Crawlers.mark_descended(ev["cr"])
		&"pvp":
			var killer: CrawlerRecord = ev["killer"]
			Events.crawler_event.emit(&"pvp_kill", killer,
				{ "summary": "%s murdered %s" % [killer.sheet.char_name, ev["cr"].sheet.char_name] })
			Crawlers.kill(ev["cr"], "slain by %s" % killer.sheet.char_name, killer)
		&"enemy_killed":
			dungeon.take_dormant_enemy(ev["zone"])
		&"looted":
			dungeon.take_dormant_box(ev["zone"])


func _post_turn() -> void:
	_resolve_crawlers()
	_advance_cohort()
	var c: CharacterData = GameState.character
	# Tick active-ability cooldowns
	for id in c.ability_cooldowns.keys():
		c.ability_cooldowns[id] = maxi(c.ability_cooldowns[id] - 1, 0)
	# Poison: burns per tick, kills if unchecked, filtered out by saferooms
	if c.statuses.has(&"poison"):
		if dungeon.grid.is_safe(dungeon.player.grid_pos):
			c.statuses.erase(&"poison")
			Events.msg("The saferoom filters the venom out of your blood. Somehow.", &"system")
		else:
			var poison: Dictionary = c.statuses[&"poison"]
			c.hp = maxi(c.hp - poison["power"], 0)
			poison["ticks"] -= 1
			Events.msg("Poison burns for %d." % poison["power"], &"combat")
			if poison["ticks"] <= 0:
				c.statuses.erase(&"poison")
				Events.msg("The poison wears off.", &"combat")
			if c.hp <= 0:
				Events.msg("The poison finishes the job. Somewhere, a rat is smug.", &"system")
				state = State.LOCKED
				Events.player_died.emit()
				return
	# Saferoom regen
	if dungeon.grid.is_safe(dungeon.player.grid_pos) and c.hp > 0:
		c.heal(2)
	dungeon.reveal_around(dungeon.player.grid_pos)
	_tick_floor_timer(c)
	Events.hud_refresh.emit()


## The shared floor clock: ACTIVE counts down, GRACE crushes stragglers,
## ENDED force-kills everyone who didn't descend. Runs every world tick (and
## every accelerated spectate step once the player has taken the stairs).
func _tick_floor_timer(c: CharacterData) -> void:
	match Crawlers.floor_state:
		Crawlers.FloorState.ACTIVE:
			if GameState.floor_turns_left > 0:
				GameState.floor_turns_left -= 1
				match GameState.floor_turns_left:
					100:
						Events.msg("REMINDER: This floor closes in 100 turns. The System suggests you stop sightseeing.", &"system")
					50:
						Events.msg("WARNING: 50 turns until floor collapse. Descending is not mandatory, but neither is survival.", &"system")
					25:
						Events.msg("URGENT: 25 turns remaining. Your life insurance does not cover 'floor'.", &"system")
					_:
						if GameState.floor_turns_left < 10:
							Events.msg("Floor collapse in %d..." % GameState.floor_turns_left, &"system")
			else:
				Crawlers.begin_grace()
				Events.msg("THE FLOOR IS NOW CLOSED. Reach a stairwell or the ceiling reaches you.", &"system")
		Crawlers.FloorState.GRACE:
			_tick_grace(c)
		Crawlers.FloorState.ENDED:
			pass


func _tick_grace(c: CharacterData) -> void:
	GameState.collapse_ticks += 1
	var dmg: int = 5 * GameState.collapse_ticks

	# The player crushes too — unless they've descended (spectating) or are
	# standing in a saferoom (protected during grace, but NOT past floor end)
	if not spectate and dungeon.player != null and is_instance_valid(dungeon.player):
		if dungeon.grid.is_safe(dungeon.player.grid_pos):
			if not _collapse_safe_notified:
				_collapse_safe_notified = true
				Events.msg("The Safe Room holds — for now. It will not survive the floor's end.", &"system")
		else:
			c.hp = maxi(c.hp - dmg, 0)
			Events.msg("The ceiling grinds downward. You take %d crush damage." % dmg, &"combat")
			if c.hp <= 0:
				state = State.LOCKED
				Events.player_died.emit()
				return
			Events.crush_survived.emit()

	_crush_npcs(dmg)

	Crawlers.grace_ticks_left -= 1
	if Crawlers.grace_ticks_left <= 0:
		_force_end_floor(c)


## Grace crush applied to every non-descended NPC crawler; saferoom-standers
## are spared during grace only.
func _crush_npcs(dmg: int) -> void:
	for cr in Crawlers.npc_records():
		if not cr.alive or cr.descended:
			continue
		if cr.tier == CrawlerRecord.Tier.REAL and cr.entity != null and is_instance_valid(cr.entity):
			if dungeon.grid.is_safe(cr.entity.grid_pos):
				continue
			damage_crawler(cr, dmg, "floor collapse")
		else:
			var room: int = dungeon.floor_data.room_of.get(cr.pos, -1)
			if _room_is_saferoom(room):
				continue
			cr.sheet.hp = maxi(cr.sheet.hp - dmg, 0)
			if cr.sheet.hp <= 0:
				Crawlers.kill(cr, "floor collapse")


func _room_is_saferoom(room: int) -> bool:
	if room < 0 or room >= dungeon.floor_data.rooms.size():
		return false
	return dungeon.floor_data.rooms[room] == dungeon.floor_data.saferoom


## The floor's hard end: anyone who didn't reach the stairs dies, saferoom or
## not (this closes the camp-forever loophole).
func _force_end_floor(c: CharacterData) -> void:
	for cr in Crawlers.npc_records():
		if not cr.alive or cr.descended:
			continue
		if cr.entity != null and is_instance_valid(cr.entity):
			dungeon.grid.remove_entity(cr.entity.grid_pos)
			dungeon.real_crawler_entities.erase(cr.entity)
			cr.entity.queue_free()
		cr.entity = null
		cr.controller = null
		cr.tier = CrawlerRecord.Tier.ABSTRACT
		Crawlers.kill(cr, "floor closure")
	Crawlers.end_floor()

	var prec := player_record()
	if not spectate and prec != null and not prec.descended:
		Events.msg("The floor closes for good. You did not make it out.", &"system")
		state = State.LOCKED
		Events.player_died.emit()


## One accelerated world tick while the player waits in the stairwell lounge:
## no player, no bubble — just the abstract cohort and the shared clock.
func spectate_step() -> void:
	if Crawlers.floor_state == Crawlers.FloorState.ENDED:
		return
	_advance_cohort()
	_tick_floor_timer(GameState.character)
	Events.cohort_changed.emit()


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
