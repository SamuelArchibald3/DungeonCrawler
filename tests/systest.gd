extends Node
## In-game system test, attached by main.gd when run with `-- --systest`.
## Exercises loot, equipment invariants, combat math, the race/class event,
## abilities, and the death path. Prints PASS/FAIL lines and quits.

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run()


func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: %s" % label)
	else:
		failures += 1
		print("FAIL: %s" % label)


func _run() -> void:
	var main := get_parent()
	var c: CharacterData = GameState.character

	# --- Loot boxes yield 1-3 items ---
	for tier in 4:
		var items: Array = LootGenerator.open_box(tier, 3)
		check(items.size() >= 1 and items.size() <= 3, "box tier %d yields 1-3 items (%d)" % [tier, items.size()])

	# --- Rarity: legendary items are fully affixed and named ---
	var legendary := LootGenerator.roll_item(3, ItemData.Rarity.LEGENDARY)
	check(legendary.affixes.size() == 4, "legendary has 4 affixes (%d)" % legendary.affixes.size())
	check(legendary.prefix != "" and legendary.suffix != "", "legendary is prefixed+suffixed: " + legendary.display_name())
	var common := LootGenerator.roll_item(1, ItemData.Rarity.COMMON)
	check(common.affixes.is_empty(), "common has no affixes")

	# --- Gold boxes skew rarer than bronze (300 samples each) ---
	var bronze_sum := 0
	var gold_sum := 0
	for i in 300:
		bronze_sum += LootGenerator.roll_rarity(0, 1)
		gold_sum += LootGenerator.roll_rarity(2, 1)
	check(gold_sum > bronze_sum, "gold rarity skews above bronze (%d vs %d)" % [gold_sum, bronze_sum])

	# --- Equip swap invariant: no item duplicated or lost ---
	var sword_a := LootGenerator.roll_item(1, ItemData.Rarity.RARE)
	while sword_a.base.slot != &"weapon":
		sword_a = LootGenerator.roll_item(1, ItemData.Rarity.RARE)
	var sword_b := LootGenerator.roll_item(1, ItemData.Rarity.RARE)
	while sword_b.base.slot != &"weapon":
		sword_b = LootGenerator.roll_item(1, ItemData.Rarity.RARE)
	c.inventory.append(sword_a)
	c.inventory.append(sword_b)
	var total_before := c.inventory.size() + _equipped_count(c)
	var inv_screen = main.inventory_screen
	inv_screen.refresh()
	inv_screen._on_inventory_activated(c.inventory.find(sword_a))
	check(c.equipment[&"weapon"] == sword_a, "equipping A fills weapon slot")
	inv_screen._on_inventory_activated(c.inventory.find(sword_b))
	check(c.equipment[&"weapon"] == sword_b, "equipping B swaps into slot")
	check(c.inventory.has(sword_a), "A returned to inventory after swap")
	check(c.inventory.size() + _equipped_count(c) == total_before, "equip swaps preserve item count")

	# --- Combat math: weapon damage raises attack, gear defense reduces hits ---
	var rat_def: EnemyDef = EnemyDef.all()[0]
	var dummy := Entity.make_enemy(rat_def, Vector2i(1, 1), 1)
	var dmg_armed := 0
	for i in 50:
		dmg_armed += Combat.player_attack_damage(c, dummy, GameState.rng)
	c.equipment[&"weapon"] = null
	var dmg_unarmed := 0
	for i in 50:
		dmg_unarmed += Combat.player_attack_damage(c, dummy, GameState.rng)
	check(dmg_armed > dmg_unarmed, "weapon increases damage (%d vs %d over 50 rolls)" % [dmg_armed, dmg_unarmed])
	dummy.free()

	# --- Enemy scaling: deeper floors mean tougher, more rewarding enemies ---
	var all_defs := EnemyDef.all()
	check(all_defs.size() == 5, "5 enemy defs exist (%d)" % all_defs.size())
	var rat_floor3 := Entity.make_enemy(all_defs[0], Vector2i(1, 1), 3)
	check(rat_floor3.max_hp > all_defs[0].max_hp, "floor-3 rat has scaled HP")
	check(rat_floor3.xp_value > all_defs[0].xp, "floor-3 rat grants scaled XP")
	rat_floor3.free()

	# --- Item comparison text ---
	var cmp: String = main.inventory_screen._comparison_text(legendary, common)
	check(cmp != "", "comparison text generated for differing items")

	# --- Reaching floor 3 triggers race/class; picking mutates the character ---
	check(not GameState.race_class_done, "race/class not done at start")
	c.gain_xp(100)
	check(c.level >= 3, "xp grants level 3+ (level %d)" % c.level)
	var dungeon = main.dungeon
	dungeon.turn_manager.maybe_trigger_race_class()  # still floor 1
	await get_tree().process_frame
	check(not main.race_class_screen.visible, "no race/class before floor 3 (even at level 3+)")
	GameState.floor_number = 3
	dungeon.turn_manager.maybe_trigger_race_class()
	await get_tree().process_frame
	check(main.race_class_screen.visible, "race/class screen opens on floor 3")
	var abilities_before := c.abilities.size()
	main.race_class_screen.debug_pick_random()  # race
	await get_tree().process_frame
	main.race_class_screen.debug_pick_random()  # class
	await get_tree().process_frame
	check(GameState.race_class_done, "race/class marked done after picks")
	check(c.race != null and c.char_class != null, "race and class assigned")
	check(c.abilities.size() > abilities_before, "abilities granted by race/class")
	check(not main.race_class_screen.visible, "race/class screen closed")
	check(dungeon.turn_manager.state == TurnManager.State.AWAITING_INPUT, "turns unlocked after selection")

	# --- Active abilities execute without errors ---
	c.hp = maxi(c.max_hp / 2, 1)
	var healed: bool = Abilities.use_active(&"heal_pulse", dungeon)
	check(healed and c.hp > c.max_hp / 2, "heal_pulse heals")
	var slammed: bool = Abilities.use_active(&"power_slam", dungeon)
	check(slammed, "power_slam executes")
	var pos_before: Vector2i = dungeon.player.grid_pos
	var stepped: bool = Abilities.use_active(&"smoke_step", dungeon)
	check(stepped and dungeon.player.grid_pos != pos_before, "smoke_step moves the player")
	check(dungeon.grid.entity_at(dungeon.player.grid_pos) == dungeon.player, "occupancy follows smoke_step")

	# --- Regression: bump-open a loot box, then walk onto its tile ---
	# (Crash found in play: opened boxes stayed in grid occupancy as freed objects)
	var box_dir := Vector2i.ZERO
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var p: Vector2i = dungeon.player.grid_pos + dir
		if dungeon.grid.is_open(p) and dungeon.grid.get_tile(p) == DungeonGrid.FLOOR:
			box_dir = dir
			break
	check(box_dir != Vector2i.ZERO, "found open tile beside player for box test")
	if box_dir != Vector2i.ZERO:
		var box_pos: Vector2i = dungeon.player.grid_pos + box_dir
		dungeon.spawn_loot_box(1, box_pos)
		check(dungeon.grid.entity_at(box_pos) is LootBox, "spawned box occupies its tile")
		var inv_before := c.inventory.size()
		var gold_before_box: int = c.gold
		dungeon.turn_manager._resolve_player(box_dir)  # bump = open
		check(c.inventory.size() > inv_before, "bumping box adds loot to inventory")
		check(c.gold > gold_before_box, "boxes pay out gold")
		check(Achievements.is_unlocked(&"first_box"), "opening a box unlocks the gambling achievement")
		await get_tree().process_frame  # let queue_free complete
		check(dungeon.grid.entity_at(box_pos) == null, "opened box leaves no stale occupancy")
		dungeon.turn_manager._resolve_player(box_dir)  # walk onto the tile (crashed before fix)
		check(dungeon.player.grid_pos == box_pos, "player can walk onto opened box tile")

	# --- Gold: kills pay out ---
	var gold_before_kill: int = c.gold
	var victim := Entity.make_enemy(EnemyDef.all()[0], Vector2i(2, 2), 1)
	dungeon.add_child(victim)
	dungeon.enemies.append(victim)
	dungeon.turn_manager._kill_enemy(victim)
	check(c.gold > gold_before_kill, "kills drop gold")
	check(Achievements.is_unlocked(&"first_blood"), "killing unlocks First Blood achievement")

	# --- Neighbourhoods: zones, per-zone enemies, bosses, map reveal ---
	var fd = dungeon.floor_data
	check(fd.zones.size() >= 2 and fd.zones.size() <= 4, "floor has 2-4 neighbourhoods (%d)" % fd.zones.size())
	var zoned_rooms := 0
	for zone_info: Dictionary in fd.zones:
		zoned_rooms += zone_info["rooms"].size()
	check(zoned_rooms == fd.rooms.size(), "every room belongs to exactly one neighbourhood")
	var all_spawns_zoned := true
	for spawn_pos: Vector2i in fd.enemy_spawns:
		if dungeon.zone_at(spawn_pos) == -1:
			all_spawns_zoned = false
	check(all_spawns_zoned, "every enemy spawn is inside a neighbourhood")

	var boss: Entity = null
	for info: Dictionary in dungeon.zones_runtime:
		if info["boss"] != null:
			boss = info["boss"]
			break
	check(boss != null, "at least one neighbourhood boss spawned")
	if boss != null:
		check(boss.is_boss and boss.max_hp >= boss.enemy_def.max_hp * 4, "boss has scaled stats")
		check(boss.boss_name != "", "boss has a name: " + boss.boss_name)
		var boss_pos: Vector2i = boss.grid_pos
		var boss_zone: int = boss.zone_index
		dungeon.turn_manager._kill_enemy(boss)
		await get_tree().process_frame
		check(dungeon.grid.entity_at(boss_pos) is LootBox, "boss death drops a guaranteed loot box")
		var zone_revealed := true
		for room: Rect2i in fd.zones[boss_zone]["rooms"]:
			if not dungeon.explored.has(room.get_center()):
				zone_revealed = false
		check(zone_revealed, "boss death reveals its district on the map")
		check(Achievements.is_unlocked(&"boss_slayer"), "boss kill unlocks Middle Management Removal")

	# --- Borough boss: guards the stairs, outclasses zone bosses, pays out ---
	var borough: Entity = dungeon.borough_boss
	check(borough != null, "borough boss spawned")
	if borough != null:
		check(borough.is_borough and borough.is_boss, "borough boss flagged correctly")
		check(borough.max_hp >= borough.enemy_def.max_hp * 8, "borough boss has 8x+ HP")
		var stairs_room_found := false
		for room: Rect2i in fd.rooms:
			if room.has_point(fd.stairs) and room.has_point(borough.grid_pos):
				stairs_room_found = true
		check(stairs_room_found, "borough boss stands in the stairs room")
		var no_zone_boss_at_stairs := true
		for info: Dictionary in dungeon.zones_runtime:
			var zb: Variant = info["boss"]
			if zb != null and is_instance_valid(zb) and zb.hp > 0:
				for room: Rect2i in fd.rooms:
					if room.has_point(fd.stairs) and room.has_point(zb.grid_pos):
						no_zone_boss_at_stairs = false
		check(no_zone_boss_at_stairs, "no neighbourhood boss shares the stairs room")
		check(dungeon.grid.get_tile(fd.stairs) == DungeonGrid.LOCKED_STAIRS, "boss stairwell starts sealed")
		check(fd.stairs_free != Vector2i(-1, -1) \
			and dungeon.grid.get_tile(fd.stairs_free) == DungeonGrid.STAIRS, "public stairwell exists and is active")
		var borough_pos: Vector2i = borough.grid_pos
		dungeon.turn_manager._kill_enemy(borough)
		await get_tree().process_frame
		check(dungeon.grid.get_tile(fd.stairs) == DungeonGrid.STAIRS, "boss death unseals his stairwell")
		var dropped: Object = dungeon.grid.entity_at(borough_pos)
		check(dropped is LootBox and (dropped as LootBox).tier == 3, "borough boss drops a platinum box")
		check(dungeon.explored.has(Vector2i(0, 0)), "borough boss death reveals the full map")
		check(Achievements.is_unlocked(&"regime_change"), "borough kill unlocks Regime Change")

	# --- Map screen ---
	check(not dungeon.explored.is_empty(), "spawn area starts explored")
	main.map_screen.open(dungeon)
	check(main.map_screen.visible, "map screen opens")
	main.map_screen.close()
	check(not main.map_screen.visible, "map screen closes")

	# --- Shop: stock, buying, selling, CHA pricing ---
	check(dungeon.shopkeeper != null, "shopkeeper spawned on the floor")
	if dungeon.shopkeeper != null:
		var keeper: Shopkeeper = dungeon.shopkeeper
		check(keeper.stock.size() == 6, "shop stocks 6 items (%d)" % keeper.stock.size())
		var shop_room: Rect2i = dungeon.floor_data.shop_room
		check(shop_room.grow(-1).has_point(keeper.grid_pos), "Bopca stands clear of the shop room's doorways")
		var intruders := false
		for e: Entity in dungeon.enemies:
			if shop_room.has_point(e.grid_pos):
				intruders = true
		check(not intruders, "no enemies spawn in the shop room")
		main.shop_screen.open_for(keeper)
		c.gold = 1000
		var stock_before: int = keeper.stock.size()
		var inv_before_buy: int = c.inventory.size()
		main.shop_screen._on_stock_activated(0)
		check(c.gold < 1000, "buying costs gold")
		check(keeper.stock.size() == stock_before - 1 and c.inventory.size() == inv_before_buy + 1,
			"bought item moves from stock to inventory")
		var gold_before_sell: int = c.gold
		main.shop_screen._on_inv_activated(c.inventory.size() - 1)
		check(c.gold > gold_before_sell, "selling grants gold")
		check(c.inventory.size() == inv_before_buy, "sold item leaves inventory")
		main.shop_screen.close()
	var priced := LootGenerator.roll_item(2, ItemData.Rarity.RARE)
	check(LootGenerator.buy_price(priced, 18) < LootGenerator.buy_price(priced, 8), "CHA discounts purchases")
	check(LootGenerator.sell_price(priced, 8) < LootGenerator.buy_price(priced, 8), "selling pays less than buying")

	# --- Guide: spawns in saferooms, tutorial pages cycle ---
	check(dungeon.guide != null or dungeon.floor_data.saferoom.size == Vector2i.ZERO,
		"guide spawns when a saferoom exists")
	main.guide_screen.open()
	check(main.guide_screen.visible, "guide screen opens")
	main.guide_screen._next_page()
	check(main.guide_screen._page == 1, "guide pages advance")
	main.guide_screen.close()
	check(not main.guide_screen.visible, "guide screen closes")

	# --- Quests: offer at guide, accept, progress via events, claim ---
	check(Quests.state == Quests.QState.NONE, "no quest before visiting the guide")
	Quests.offer(dungeon)
	check(Quests.state == Quests.QState.OFFERED, "guide offers a floor quest")
	check(Quests.data["reward_gold"] > 0, "quest posts a gold reward: " + str(Quests.data["desc"]))
	Quests.accept()
	check(Quests.state == Quests.QState.ACTIVE, "quest accepted")
	match Quests.data["type"]:
		"kill":
			for i in Quests.data["needed"]:
				Events.enemy_killed.emit(Quests.data["target_def"], false)
		"boss":
			Events.enemy_killed.emit(Quests.data["target_def"], true)
		"boxes":
			for i in Quests.data["needed"]:
				Events.box_opened.emit(0)
	check(Quests.state == Quests.QState.COMPLETE, "quest completes when the target is met")
	var gold_before_quest: int = c.gold
	var quest_reward: int = Quests.data["reward_gold"]
	Quests.claim()
	check(Quests.state == Quests.QState.CLAIMED, "quest reward claimed at the guide")
	check(c.gold == gold_before_quest + quest_reward, "quest pays the posted reward")
	check(Quests.status_line() == "", "no HUD quest line after claiming")

	# --- Achievements screen ---
	main.achievements_screen.open()
	check(main.achievements_screen.visible, "achievements screen opens")
	main.achievements_screen.close()
	check(not main.achievements_screen.visible, "achievements screen closes")

	# --- Saferooms: regen, crush immunity, enemies stay out ---
	var safe_pos := Vector2i(-1, -1)
	var lurk_pos := Vector2i(-1, -1)
	for y in dungeon.grid.height:
		for x in dungeon.grid.width:
			var p := Vector2i(x, y)
			if not (dungeon.grid.is_safe(p) and dungeon.grid.is_open(p)):
				continue
			for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var n: Vector2i = p + dir
				if dungeon.grid.is_walkable(n) and not dungeon.grid.is_safe(n) and dungeon.grid.is_open(n):
					safe_pos = p
					lurk_pos = n
					break
			if safe_pos != Vector2i(-1, -1):
				break
		if safe_pos != Vector2i(-1, -1):
			break
	check(safe_pos != Vector2i(-1, -1), "floor has a saferoom with an entrance")
	if safe_pos != Vector2i(-1, -1):
		var return_pos: Vector2i = dungeon.player.grid_pos
		dungeon.grid.move_entity(dungeon.player, return_pos, safe_pos)
		dungeon.player.set_grid_pos(safe_pos, false)

		GameState.floor_turns_left = 200
		c.hp = maxi(c.max_hp - 10, 1)
		var hp_before_regen: int = c.hp
		dungeon.turn_manager._post_turn()
		check(c.hp > hp_before_regen, "saferoom regenerates HP each turn")

		GameState.floor_turns_left = 0
		GameState.collapse_ticks = 0
		var hp_before_crush: int = c.hp
		dungeon.turn_manager._post_turn()
		check(c.hp >= hp_before_crush, "saferoom blocks collapse crush damage")

		var lurker := Entity.make_enemy(EnemyDef.all()[0], lurk_pos, 1)
		dungeon.grid.place_entity(lurker, lurk_pos)
		var hp_before_lurk: int = c.hp
		EnemyAI.act(lurker, dungeon)
		check(c.hp == hp_before_lurk, "enemy cannot attack a player inside a saferoom")
		check(not dungeon.grid.is_safe(lurker.grid_pos), "enemy refuses to enter the saferoom")
		dungeon.grid.remove_entity(lurker.grid_pos)
		lurker.free()

		dungeon.grid.move_entity(dungeon.player, safe_pos, return_pos)
		dungeon.player.set_grid_pos(return_pos, false)
		c.hp = c.max_hp

	# --- Floor timer: ticks down, collapse deals escalating damage ---
	GameState.floor_turns_left = 12
	GameState.collapse_ticks = 0
	dungeon.turn_manager._post_turn()
	check(GameState.floor_turns_left == 11, "floor timer ticks down each turn")
	c.hp = c.max_hp
	GameState.floor_turns_left = 0
	dungeon.turn_manager._post_turn()
	var after_first_crush: int = c.hp
	check(after_first_crush < c.max_hp, "collapsed floor deals crush damage")
	dungeon.turn_manager._post_turn()
	check(after_first_crush - c.hp > c.max_hp - after_first_crush, "crush damage escalates per turn")
	GameState.floor_number = 3
	GameState.start_floor_timer()
	check(GameState.floor_turns_left == 400, "floor 3 budget is 340 + 2*30 (%d)" % GameState.floor_turns_left)
	check(GameState.collapse_ticks == 0, "descending resets collapse state")
	c.hp = c.max_hp

	# --- Death path shows game over ---
	c.hp = 0
	Events.player_died.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.game_over_screen.visible, "death shows game over screen")

	if failures == 0:
		print("SYSTEST: ALL PASSED")
	else:
		print("SYSTEST: %d FAILURES" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _equipped_count(c: CharacterData) -> int:
	var count := 0
	for slot in c.equipment:
		if c.equipment[slot] != null:
			count += 1
	return count
