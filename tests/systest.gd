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

	# --- Item levels: deeper drops are stronger and pricier ---
	var shallow := LootGenerator.roll_item(1, ItemData.Rarity.COMMON)
	var deep := LootGenerator.roll_item(6, ItemData.Rarity.COMMON)
	check(deep.item_level > shallow.item_level, "deeper floors drop higher item levels (%d > %d)" % [deep.item_level, shallow.item_level])
	var low_lvl := ItemData.new()
	low_lvl.base = LootGenerator.get_def(&"rusty_sword")
	low_lvl.item_level = 1
	var high_lvl := ItemData.new()
	high_lvl.base = LootGenerator.get_def(&"rusty_sword")
	high_lvl.item_level = 7
	check(high_lvl.get_damage() > low_lvl.get_damage(), "item level raises weapon damage (%d > %d)" % [high_lvl.get_damage(), low_lvl.get_damage()])
	check(LootGenerator.price_of(high_lvl) > LootGenerator.price_of(low_lvl), "higher item level costs more")
	check(high_lvl.describe().contains("L7"), "describe shows the item level")
	var boosted: Array = LootGenerator.open_box(3, 2)
	var boosted_ok := true
	for it: ItemData in boosted:
		if not it.is_consumable() and it.item_level < 4:
			boosted_ok = false
	check(boosted_ok, "platinum boxes drop above-floor item levels")
	check(LootGenerator.make_potion().item_level == 0, "consumables are unleveled")

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
	check(all_defs.size() == 6, "6 enemy defs exist (%d)" % all_defs.size())
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

	# Spawn room must be empty: no enemies (incl. bosses), boxes, or shopkeeper
	var spawn_room: Rect2i = fd.rooms[0]
	var spawn_room_clear := true
	for e: Entity in dungeon.enemies:
		if spawn_room.has_point(e.grid_pos):
			spawn_room_clear = false
	if dungeon.shopkeeper != null and spawn_room.has_point(dungeon.shopkeeper.grid_pos):
		spawn_room_clear = false
	for box_spawn: Dictionary in fd.box_spawns:
		if spawn_room.has_point(box_spawn["pos"]):
			spawn_room_clear = false
	check(spawn_room_clear, "spawn room is empty of enemies, bosses, boxes, and shops")

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

	# --- Fame: alien-scale viewers, CHA multiplier, milestone fan boxes ---
	check(Fame.viewers >= 3_000_000, "run starts with millions of bored aliens")
	var viewers_before: int = Fame.viewers
	Events.enemy_killed.emit(&"rat", false)
	check(Fame.viewers > viewers_before, "kills attract viewers")
	var cha_saved: int = c.base_stats[&"CHA"]
	c.base_stats[&"CHA"] = 8
	var mult_low: float = Fame.multiplier()
	c.base_stats[&"CHA"] = 18
	check(Fame.multiplier() > mult_low, "CHA multiplies viewer gains")
	c.base_stats[&"CHA"] = cha_saved
	Fame.viewers = 99_000_000
	Fame.next_milestone = 0
	var inv_before_fan: int = c.inventory.size()
	var gold_before_fan: int = c.gold
	Fame.gain(10)
	check(Fame.next_milestone >= 1, "viewer milestone crossed at 100M")
	check(c.inventory.size() > inv_before_fan, "fan box delivers items")
	check(c.gold > gold_before_fan, "fans send gold")
	check(Fame.format_viewers(1_500_000_000) == "1.5B", "viewer counts format as 1.5B")
	check(Fame.format_viewers(2_000_000_000_000_000) == "2.0Q", "quadrillions format as 2.0Q")
	Fame.viewers = 999_999_999
	Fame.next_milestone = 2  # only the 1B+ milestones remain
	Fame.gain(10)
	check(Achievements.is_unlocked(&"billion_club"), "a billion viewers unlocks The Billion Club")

	# --- Announcer: events become notification boxes ---
	Events.announce.emit("TEST BOX", "Just testing. The System loves tests.")
	await get_tree().process_frame
	check(main.notification_box.queue_size() > 0, "notifications queue and display")
	var viewers_before_level: int = Fame.viewers
	Events.level_up.emit(99)
	await get_tree().process_frame
	check(Fame.viewers > viewers_before_level, "level-ups gain viewers")

	# --- Saferoom amenities: paid run-long buffs at the guide ---
	check(GameState.amenities.is_empty(), "runs start with no amenities")
	c.gold = 500
	var guide_ui = main.guide_screen
	var hp_before_cot: int = c.max_hp
	var gold_before_cot: int = c.gold
	guide_ui._on_amenity_pressed(&"cot")
	check(c.max_hp == hp_before_cot + 10, "cot nap grants +10 max HP")
	check(c.gold == gold_before_cot - 25, "cot nap costs 25 gold")
	var gold_after_cot: int = c.gold
	guide_ui._on_amenity_pressed(&"cot")
	check(c.gold == gold_after_cot, "amenities are once per run")
	var mult_before_shower: float = Fame.multiplier()
	guide_ui._on_amenity_pressed(&"shower")
	check(is_equal_approx(Fame.multiplier(), mult_before_shower + 0.25), "shower adds +25% viewer gains")
	var rat_dummy := Entity.make_enemy(EnemyDef.all()[0], Vector2i(1, 1), 1)
	var saved_abilities := c.abilities.duplicate()
	c.abilities.clear()  # passives like backstab would skew the exact-diff check
	GameState.rng.seed = 12345
	var dmg_unfed := 0
	for i in 20:
		dmg_unfed += Combat.player_attack_damage(c, rat_dummy, GameState.rng)
	guide_ui._on_amenity_pressed(&"meal")
	GameState.rng.seed = 12345
	var dmg_fed := 0
	for i in 20:
		dmg_fed += Combat.player_attack_damage(c, rat_dummy, GameState.rng)
	c.abilities = saved_abilities
	rat_dummy.free()
	check(dmg_fed == dmg_unfed + 20, "hot meal adds exactly +1 damage per hit")
	check(Achievements.is_unlocked(&"self_care"), "buying all amenities unlocks Self Care")

	# --- Stat points: banked on level up, spendable only in saferooms ---
	check(c.unspent_stat_points == (c.level - 1) * 2,
		"level ups bank 2 stat points each (%d pts at level %d)" % [c.unspent_stat_points, c.level])
	main.inventory_screen.refresh()
	var str_before: int = c.base_stats[&"STR"]
	main.inventory_screen.allocate_allowed = false
	main.inventory_screen._on_stat_plus(&"STR")
	check(c.base_stats[&"STR"] == str_before, "cannot allocate stat points outside a saferoom")
	main.inventory_screen.allocate_allowed = true
	var pts_before: int = c.unspent_stat_points
	main.inventory_screen._on_stat_plus(&"STR")
	check(c.base_stats[&"STR"] == str_before + 1, "allocating in a saferoom raises the stat")
	check(c.unspent_stat_points == pts_before - 1, "allocation spends a point")
	var hp_before_con: int = c.max_hp
	main.inventory_screen._on_stat_plus(&"CON")
	check(c.max_hp > hp_before_con, "CON allocation raises max HP")
	main.inventory_screen.allocate_allowed = false

	# --- Character sheet: gear bonuses split out as a green column ---
	var medal := ItemData.new()
	medal.base = LootGenerator.get_def(&"participation_medal")  # innate CHA +1
	c.inventory.append(medal)
	main.inventory_screen.refresh()
	main.inventory_screen._on_inventory_activated(c.inventory.size() - 1)  # equip to trinket
	check(c.get_gear_bonus(&"CHA") >= 1, "gear stat bonus tracked separately from base")
	check(c.get_stat(&"CHA") == (c.get_stat(&"CHA") - c.get_gear_bonus(&"CHA")) + c.get_gear_bonus(&"CHA"),
		"base + gear equals total")
	main.inventory_screen.refresh()
	var cha_bonus_text: String = main.inventory_screen._stat_rows[&"CHA"]["bonus"].text
	check(cha_bonus_text.begins_with("+"), "gear bonus renders as +N in its column (%s)" % cha_bonus_text)
	var cha_total_text: String = main.inventory_screen._stat_rows[&"CHA"]["total"].text
	check(cha_total_text == str(c.get_stat(&"CHA")), "total column shows the final stat")

	# --- Item type column and sortable lists ---
	check(LootGenerator.make_potion().type_label() == "consumable", "potions typed as consumable")
	var typed_sword := ItemData.new()
	typed_sword.base = LootGenerator.get_def(&"rusty_sword")
	check(typed_sword.type_label() == "equip: weapon", "gear typed with its slot")
	var saved_inventory: Array = c.inventory
	var typed_helm := ItemData.new()
	typed_helm.base = LootGenerator.get_def(&"pot_helm")
	c.inventory = [LootGenerator.make_potion(), typed_helm, typed_sword]
	main.inventory_screen.refresh()
	var inv_tree: ItemTree = main.inventory_screen._inv_list
	inv_tree._on_title_clicked(1, MOUSE_BUTTON_LEFT)  # sort by Type
	var first_row := inv_tree.get_root().get_first_child()
	check(first_row.get_text(1) == "equip: weapon", "type sort lists weapons first (%s)" % first_row.get_text(1))
	var last_row := first_row
	while last_row.get_next() != null:
		last_row = last_row.get_next()
	check(last_row.get_text(1) == "consumable", "type sort lists consumables last")
	check(c.inventory[first_row.get_metadata(0)] == typed_sword, "sorted rows still map to source items")
	c.inventory = saved_inventory
	main.inventory_screen.refresh()

	# Price sorting in the shop
	if dungeon.shopkeeper != null:
		main.shop_screen.open_for(dungeon.shopkeeper)
		var stock_tree: ItemTree = main.shop_screen._stock_list
		stock_tree._on_title_clicked(2, MOUSE_BUTTON_LEFT)  # sort by Price ascending
		var cheap_row := stock_tree.get_root().get_first_child()
		var dear_row := cheap_row
		while dear_row.get_next() != null:
			dear_row = dear_row.get_next()
		var cheap: int = LootGenerator.buy_price(dungeon.shopkeeper.stock[cheap_row.get_metadata(0)], c.get_stat(&"CHA"))
		var dear: int = LootGenerator.buy_price(dungeon.shopkeeper.stock[dear_row.get_metadata(0)], c.get_stat(&"CHA"))
		check(cheap <= dear, "price sort orders cheapest first (%d <= %d)" % [cheap, dear])
		main.shop_screen.close()

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

	# --- Ticked real-time mode: world acts without input, player rate-limited ---
	var tm: TurnManager = dungeon.turn_manager
	GameState.realtime_mode = true
	tm.set_process(false)  # engine frames stay out; we drive ticks manually
	tm.state = TurnManager.State.AWAITING_INPUT
	GameState.floor_turns_left = 200
	c.hp = c.max_hp
	var rt_adj := Vector2i(-1, -1)
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var p: Vector2i = dungeon.player.grid_pos + dir
		if dungeon.grid.is_open(p) and not dungeon.grid.is_safe(p) \
				and dungeon.grid.get_tile(p) == DungeonGrid.FLOOR:
			rt_adj = p
			break
	check(rt_adj != Vector2i(-1, -1), "open tile beside player for realtime test")
	if rt_adj != Vector2i(-1, -1):
		var rt_rat := Entity.make_enemy(EnemyDef.all()[0], rt_adj, 1)
		dungeon.add_child(rt_rat)
		dungeon.grid.place_entity(rt_rat, rt_adj)
		dungeon.enemies.append(rt_rat)
		var hp_before_rt: int = c.hp
		for i in 6:
			tm._process(0.5)  # each call spans at least one world tick
		check(c.hp < hp_before_rt, "enemies act on world ticks without player input")
		check(GameState.floor_turns_left < 200, "floor timer runs on world ticks")
		# Player movement: held key acts immediately, then rate-limited
		var move_dir := Vector2i.ZERO
		var move_action := ""
		for action: String in TurnManager.DIRECTION_ACTIONS:
			var dir: Vector2i = TurnManager.DIRECTION_ACTIONS[action]
			var p: Vector2i = dungeon.player.grid_pos + dir
			if dungeon.grid.is_open(p):
				move_dir = dir
				move_action = action
				break
		if move_action != "":
			var start_pos: Vector2i = dungeon.player.grid_pos
			Input.action_press(move_action)
			tm._process(0.01)
			check(dungeon.player.grid_pos == start_pos + move_dir, "held key moves the player in realtime")
			var after_first: Vector2i = dungeon.player.grid_pos
			tm._process(0.05)
			check(dungeon.player.grid_pos == after_first, "player action cooldown limits move rate")
			Input.action_release(move_action)
		if is_instance_valid(rt_rat):
			dungeon.grid.remove_entity(rt_rat.grid_pos)
			dungeon.enemies.erase(rt_rat)
			rt_rat.queue_free()
	GameState.realtime_mode = false
	tm.set_process(true)
	c.hp = c.max_hp

	# --- Enemy health bars: appear on damage, shift green -> red ---
	var bar_rat := Entity.make_enemy(EnemyDef.all()[0], Vector2i(3, 3), 1)
	dungeon.add_child(bar_rat)
	await get_tree().process_frame
	check(not bar_rat.health_bar_visible(), "health bar hidden at full HP")
	bar_rat.hp = int(bar_rat.max_hp / 2.0)
	check(bar_rat.health_bar_visible(), "health bar appears once damaged")
	var half_hp_color: Color = bar_rat.health_bar_color()
	bar_rat.hp = 1
	var low_hp_color: Color = bar_rat.health_bar_color()
	check(low_hp_color.r > half_hp_color.r and low_hp_color.g < half_hp_color.g,
		"health bar shifts from green toward red as HP drops")
	bar_rat.queue_free()

	# --- Line of sight: clear corridors pass, walls block ---
	var los_grid := DungeonGrid.new(5, 3)
	for x in 5:
		los_grid.set_tile(Vector2i(x, 1), DungeonGrid.FLOOR)
	check(los_grid.has_line_of_sight(Vector2i(0, 1), Vector2i(4, 1)), "clear corridor has line of sight")
	los_grid.set_tile(Vector2i(2, 1), DungeonGrid.WALL)
	check(not los_grid.has_line_of_sight(Vector2i(0, 1), Vector2i(4, 1)), "walls block line of sight")

	# --- Telegraphs: heavies wind up, strikes miss if you move ---
	var dex_saved: int = c.base_stats[&"DEX"]
	c.base_stats[&"DEX"] = 0  # no dodges skewing the checks
	var brute_def: EnemyDef = null
	for d: EnemyDef in EnemyDef.all():
		if d.id == &"skeleton_brute":
			brute_def = d
	check(brute_def != null and brute_def.telegraphs, "skeleton brute telegraphs its hits")
	brute_def.move_every_n_turns = 1  # local instance: act every call for the test
	var tel_adj := Vector2i(-1, -1)
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var p: Vector2i = dungeon.player.grid_pos + dir
		if dungeon.grid.is_open(p) and not dungeon.grid.is_safe(p):
			tel_adj = p
			break
	check(tel_adj != Vector2i(-1, -1), "open tile beside player for telegraph test")
	if tel_adj != Vector2i(-1, -1):
		var brute := Entity.make_enemy(brute_def, tel_adj, 1)
		dungeon.add_child(brute)
		dungeon.grid.place_entity(brute, tel_adj)
		c.hp = c.max_hp
		EnemyAI.act(brute, dungeon)
		check(brute.winding_up and c.hp == c.max_hp, "heavy attack winds up instead of hitting")
		EnemyAI.act(brute, dungeon)
		check(c.hp < c.max_hp, "telegraphed strike lands if you stand still")
		check(not brute.winding_up, "windup clears after striking")
		c.hp = c.max_hp
		EnemyAI.act(brute, dungeon)
		check(brute.winding_up, "brute winds up again")
		var dodge_spot := Vector2i(-1, -1)
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var p: Vector2i = dungeon.player.grid_pos + dir
			if p != brute.grid_pos and dungeon.grid.is_open(p):
				dodge_spot = p
				break
		if dodge_spot != Vector2i(-1, -1):
			var pre_dodge_pos: Vector2i = dungeon.player.grid_pos
			dungeon.grid.move_entity(dungeon.player, pre_dodge_pos, dodge_spot)
			dungeon.player.set_grid_pos(dodge_spot, false)
			EnemyAI.act(brute, dungeon)
			check(c.hp == c.max_hp, "telegraphed strike misses if you move")
			dungeon.grid.move_entity(dungeon.player, dodge_spot, pre_dodge_pos)
			dungeon.player.set_grid_pos(pre_dodge_pos, false)
		dungeon.grid.remove_entity(brute.grid_pos)
		brute.queue_free()

	# --- Ranged enemy: spits from distance, flees when crowded ---
	var spitter_def: EnemyDef = null
	for d: EnemyDef in EnemyDef.all():
		if d.id == &"goblin_spitter":
			spitter_def = d
	check(spitter_def != null and spitter_def.ranged, "goblin spitter is a ranged enemy")
	var range_row := Vector2i(-1, -1)
	for room: Rect2i in fd.rooms:
		if room == fd.saferoom or room == fd.shop_room:
			continue
		for ry in range(room.position.y, room.end.y):
			var all_open := true
			for rx in range(room.position.x, room.position.x + 4):
				if not dungeon.grid.is_open(Vector2i(rx, ry)):
					all_open = false
					break
			if all_open and room.size.x >= 4:
				range_row = Vector2i(room.position.x, ry)
				break
		if range_row != Vector2i(-1, -1):
			break
	check(range_row != Vector2i(-1, -1), "found an open row for the ranged test")
	if range_row != Vector2i(-1, -1):
		var player_home: Vector2i = dungeon.player.grid_pos
		dungeon.grid.move_entity(dungeon.player, player_home, range_row)
		dungeon.player.set_grid_pos(range_row, false)
		var spit_pos := range_row + Vector2i(3, 0)
		var spitter := Entity.make_enemy(spitter_def, spit_pos, 2)
		dungeon.add_child(spitter)
		dungeon.grid.place_entity(spitter, spit_pos)
		c.hp = c.max_hp
		EnemyAI.act(spitter, dungeon)
		check(c.hp < c.max_hp, "spitter hits from 3 tiles away")
		var crowd_pos := range_row + Vector2i(1, 0)
		dungeon.grid.move_entity(spitter, spitter.grid_pos, crowd_pos)
		spitter.set_grid_pos(crowd_pos, false)
		EnemyAI.act(spitter, dungeon)
		var flee_dist := maxi(absi(spitter.grid_pos.x - range_row.x), absi(spitter.grid_pos.y - range_row.y))
		check(flee_dist > 1, "crowded spitter retreats (dist %d)" % flee_dist)
		dungeon.grid.remove_entity(spitter.grid_pos)
		spitter.queue_free()
		dungeon.grid.move_entity(dungeon.player, dungeon.player.grid_pos, player_home)
		dungeon.player.set_grid_pos(player_home, false)
	c.base_stats[&"DEX"] = dex_saved
	c.hp = c.max_hp

	# --- Button attacks, knockback, wall slams ---
	if range_row != Vector2i(-1, -1):
		var p0 := range_row
		var p1 := range_row + Vector2i(1, 0)
		var p2 := range_row + Vector2i(2, 0)
		var attack_home: Vector2i = dungeon.player.grid_pos
		dungeon.grid.move_entity(dungeon.player, attack_home, p0)
		dungeon.player.set_grid_pos(p0, false)
		dungeon.player.set_facing(Vector2i.RIGHT)

		var kb_rat := Entity.make_enemy(EnemyDef.all()[0], p1, 1)
		kb_rat.max_hp = 99
		kb_rat.hp = 99
		dungeon.add_child(kb_rat)
		dungeon.grid.place_entity(kb_rat, p1)
		dungeon.turn_manager._resolve_attack()
		check(kb_rat.hp < 99, "button attack hits the faced tile")
		check(kb_rat.grid_pos == p2, "hit shoves the rat back a tile")
		check(dungeon.grid.entity_at(p2) == kb_rat, "occupancy follows knockback")
		check(dungeon.turn_manager._resolve_player(Vector2i.RIGHT), "player steps into the vacated tile")
		check(not dungeon.turn_manager._resolve_player(Vector2i.RIGHT), "walking into an enemy blocks instead of attacking")
		dungeon.grid.move_entity(dungeon.player, dungeon.player.grid_pos, p0)
		dungeon.player.set_grid_pos(p0, false)
		dungeon.grid.remove_entity(kb_rat.grid_pos)
		kb_rat.queue_free()

		# Baseline damage with room to be shoved, then the same swing into a wall
		var base_rat := Entity.make_enemy(EnemyDef.all()[0], p1, 1)
		base_rat.max_hp = 99
		base_rat.hp = 99
		dungeon.add_child(base_rat)
		dungeon.grid.place_entity(base_rat, p1)
		GameState.rng.seed = 777
		dungeon.turn_manager._resolve_attack()
		var loss_open: int = 99 - base_rat.hp
		dungeon.grid.remove_entity(base_rat.grid_pos)
		base_rat.queue_free()

		var slam_pos := Vector2i(-1, -1)
		var slam_dir := Vector2i.ZERO
		for y in dungeon.grid.height:
			for x in dungeon.grid.width:
				var pos := Vector2i(x, y)
				for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					if dungeon.grid.is_open(pos) and not dungeon.grid.is_safe(pos) \
							and dungeon.grid.get_tile(pos + dir) == DungeonGrid.WALL \
							and dungeon.grid.is_open(pos - dir) and not dungeon.grid.is_safe(pos - dir):
						slam_pos = pos
						slam_dir = dir
						break
				if slam_pos != Vector2i(-1, -1):
					break
			if slam_pos != Vector2i(-1, -1):
				break
		check(slam_pos != Vector2i(-1, -1), "found a wall-backed tile for the slam test")
		if slam_pos != Vector2i(-1, -1):
			dungeon.grid.move_entity(dungeon.player, dungeon.player.grid_pos, slam_pos - slam_dir)
			dungeon.player.set_grid_pos(slam_pos - slam_dir, false)
			dungeon.player.set_facing(slam_dir)
			var slam_rat := Entity.make_enemy(EnemyDef.all()[0], slam_pos, 1)
			slam_rat.max_hp = 99
			slam_rat.hp = 99
			dungeon.add_child(slam_rat)
			dungeon.grid.place_entity(slam_rat, slam_pos)
			GameState.rng.seed = 777
			dungeon.turn_manager._resolve_attack()
			var loss_wall: int = 99 - slam_rat.hp
			check(loss_wall == loss_open + 3, "wall slam adds +3 damage (%d vs %d)" % [loss_wall, loss_open])
			dungeon.grid.remove_entity(slam_rat.grid_pos)
			slam_rat.queue_free()
			dungeon.grid.move_entity(dungeon.player, dungeon.player.grid_pos, p0)
			dungeon.player.set_grid_pos(p0, false)
			dungeon.player.set_facing(Vector2i.RIGHT)

		# Heavies stand firm — unless caught mid-windup
		var firm_brute := Entity.make_enemy(brute_def, p1, 1)
		firm_brute.max_hp = 99
		firm_brute.hp = 99
		dungeon.add_child(firm_brute)
		dungeon.grid.place_entity(firm_brute, p1)
		dungeon.turn_manager._resolve_attack()
		check(firm_brute.grid_pos == p1, "heavies resist knockback")
		firm_brute.winding_up = true
		firm_brute.set_telegraphing(true)
		dungeon.turn_manager._resolve_attack()
		check(firm_brute.grid_pos == p2 and not firm_brute.winding_up, "shoving a winding heavy interrupts the telegraph")
		dungeon.grid.remove_entity(firm_brute.grid_pos)
		firm_brute.queue_free()
		dungeon.grid.move_entity(dungeon.player, dungeon.player.grid_pos, attack_home)
		dungeon.player.set_grid_pos(attack_home, false)
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
