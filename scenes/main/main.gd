extends Node
## App shell: screen switching, run lifecycle, floor transitions.
## Pass `--autorun` as a user arg (after `--`) for a headless chaos test that
## plays random moves and clicks through every modal.

var screen_root: Node
var ui_layer: CanvasLayer
var hud: Hud
var message_log: MessageLog
var inventory_screen: InventoryScreen
var shop_screen: ShopScreen
var guide_screen: GuideScreen
var map_screen: MapScreen
var achievements_screen: AchievementsScreen
var notification_box: NotificationBox
var race_class_screen: RaceClassScreen
var game_over_screen: GameOverScreen
var char_create_screen: CharCreateScreen
var dungeon: Dungeon

var _autorun := false
var _autorun_frames := 0
var _autorun_rng := RandomNumberGenerator.new()
var _shot_mode := false


func _ready() -> void:
	_autorun = OS.get_cmdline_user_args().has("--autorun")

	screen_root = Node.new()
	screen_root.name = "ScreenRoot"
	add_child(screen_root)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	hud = Hud.new()
	hud.visible = false
	ui_layer.add_child(hud)

	message_log = MessageLog.new()
	message_log.visible = false
	ui_layer.add_child(message_log)

	inventory_screen = InventoryScreen.new()
	inventory_screen.closed.connect(_on_inventory_closed)
	ui_layer.add_child(inventory_screen)

	shop_screen = ShopScreen.new()
	shop_screen.closed.connect(_on_modal_closed)
	ui_layer.add_child(shop_screen)

	guide_screen = GuideScreen.new()
	guide_screen.closed.connect(_on_modal_closed)
	ui_layer.add_child(guide_screen)

	map_screen = MapScreen.new()
	map_screen.closed.connect(_on_modal_closed)
	ui_layer.add_child(map_screen)

	achievements_screen = AchievementsScreen.new()
	achievements_screen.closed.connect(_on_modal_closed)
	ui_layer.add_child(achievements_screen)

	race_class_screen = RaceClassScreen.new()
	race_class_screen.done.connect(_on_race_class_done)
	ui_layer.add_child(race_class_screen)

	game_over_screen = GameOverScreen.new()
	game_over_screen.new_crawler_requested.connect(show_char_create)
	ui_layer.add_child(game_over_screen)

	char_create_screen = CharCreateScreen.new()
	char_create_screen.confirmed.connect(start_run)
	char_create_screen.visible = false
	ui_layer.add_child(char_create_screen)

	# Last child = drawn on top of everything, including modals
	notification_box = NotificationBox.new()
	ui_layer.add_child(notification_box)

	Events.player_died.connect(_on_player_died)

	if _autorun:
		GameState.realtime_mode = false  # chaos test drives discrete turns
		_autorun_rng.randomize()
		start_run(CharGenerator.random_character())
	elif OS.get_cmdline_user_args().has("--screenshots"):
		GameState.realtime_mode = false
		_shot_mode = true
		start_run(CharGenerator.random_character())
		# Some sample loot so the inventory screenshot isn't empty
		for i in 5:
			GameState.character.inventory.append(
				LootGenerator.roll_item(2, LootGenerator.roll_rarity(i % 4, 2)))
		GameState.character.inventory.append(LootGenerator.make_potion())
		# Equipped baton + rare sword in slot 0, so the comparison panel renders
		var baton := ItemData.new()
		baton.base = LootGenerator.get_def(&"crawler_baton")
		GameState.character.equipment[&"weapon"] = baton
		var sword := ItemData.new()
		sword.base = LootGenerator.get_def(&"rusty_sword")
		sword.rarity = ItemData.Rarity.RARE
		sword.item_level = 3
		LootGenerator._roll_affixes(sword)
		GameState.character.inventory.insert(0, sword)
		var foot := ItemData.new()
		foot.base = LootGenerator.get_def(&"lucky_rabbit_foot")
		foot.item_level = 4
		GameState.character.equipment[&"trinket"] = foot
		# Jump to floor 3 (race/class suppressed) so the shot shows the spawn saferoom
		GameState.race_class_done = true
		GameState.floor_number = 3
		_load_floor()
	elif OS.get_cmdline_user_args().has("--systest"):
		GameState.realtime_mode = false  # deterministic; realtime tested explicitly
		start_run(CharGenerator.random_character())
		add_child(load("res://tests/systest.gd").new())
	else:
		show_char_create()


func show_char_create() -> void:
	game_over_screen.close()
	_clear_dungeon()
	hud.visible = false
	message_log.visible = false
	char_create_screen.visible = true


func start_run(character: CharacterData) -> void:
	char_create_screen.visible = false
	GameState.new_run(character)
	hud.visible = true
	message_log.visible = true
	_load_floor()
	Events.msg(Flavor.welcome(character.char_name), &"system")


func _clear_dungeon() -> void:
	if is_instance_valid(dungeon):
		dungeon.queue_free()
	dungeon = null


func _load_floor() -> void:
	_clear_dungeon()
	GameState.start_floor_timer()
	dungeon = Dungeon.new()
	screen_root.add_child(dungeon)
	dungeon.descend_requested.connect(_on_descend)
	dungeon.race_class_requested.connect(_on_race_class_requested)
	dungeon.shop_requested.connect(_on_shop_requested)
	dungeon.guide_requested.connect(_on_guide_requested)
	Events.floor_changed.emit(GameState.floor_number)
	Events.msg("This floor closes in %d turns. The System recommends cardio." % GameState.floor_turns_left, &"system")


func _on_descend() -> void:
	Events.descended.emit(GameState.floor_turns_left)
	GameState.floor_number += 1
	Events.msg("You descend to floor %d." % GameState.floor_number, &"system")
	if GameState.floor_number == 5:
		Events.msg("PROTOTYPE DEPTHS CLEARED. The System is genuinely surprised. Keep descending if you like pain.", &"system")
	elif randf() < 0.4:
		Events.msg(Flavor.carl_news(), &"system")
	call_deferred("_load_floor")


func _on_player_died() -> void:
	Events.msg("You have died. %s" % Flavor.eulogy(), &"system")
	call_deferred("_show_game_over")


func _show_game_over() -> void:
	_clear_dungeon()
	game_over_screen.open()


func _on_race_class_requested() -> void:
	race_class_screen.open()


func _on_race_class_done() -> void:
	if is_instance_valid(dungeon) and dungeon.turn_manager != null:
		dungeon.turn_manager.unlock()


func _on_shop_requested(keeper: Shopkeeper) -> void:
	if is_instance_valid(dungeon) and dungeon.turn_manager != null:
		dungeon.turn_manager.lock()
	shop_screen.open_for(keeper)


func _on_guide_requested() -> void:
	if is_instance_valid(dungeon) and dungeon.turn_manager != null:
		dungeon.turn_manager.lock()
	guide_screen.open(dungeon)


func _on_modal_closed() -> void:
	if is_instance_valid(dungeon) and dungeon.turn_manager != null:
		dungeon.turn_manager.unlock()


func _on_inventory_closed() -> void:
	if is_instance_valid(dungeon) and dungeon.turn_manager != null:
		dungeon.turn_manager.unlock()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if inventory_screen.visible:
			return  # the screen closes itself
		if _can_open_modal():
			dungeon.turn_manager.lock()
			inventory_screen.allocate_allowed = dungeon.grid.is_safe(dungeon.player.grid_pos)
			inventory_screen.open()
	elif event.is_action_pressed("map"):
		if map_screen.visible:
			return  # the screen closes itself
		if _can_open_modal():
			dungeon.turn_manager.lock()
			map_screen.open(dungeon)
	elif event.is_action_pressed("achievements"):
		if achievements_screen.visible:
			return  # the screen closes itself
		if _can_open_modal():
			dungeon.turn_manager.lock()
			achievements_screen.open()
	elif event.is_action_pressed("toggle_pace"):
		GameState.realtime_mode = not GameState.realtime_mode
		var mode_name := "REAL-TIME" if GameState.realtime_mode else "TURN-BASED"
		Events.msg("Pacing switched to %s." % mode_name, &"system")
		Events.announce.emit("PACING: %s" % mode_name,
			"The System accommodates your tempo preferences. Reluctantly.")


func _can_open_modal() -> bool:
	return is_instance_valid(dungeon) and dungeon.turn_manager != null \
		and dungeon.turn_manager.state == TurnManager.State.AWAITING_INPUT \
		and not race_class_screen.visible and not game_over_screen.visible \
		and not shop_screen.visible and not guide_screen.visible \
		and not achievements_screen.visible


func _process(_delta: float) -> void:
	if _shot_mode:
		_shot_tick()
		return
	if not _autorun:
		return
	_autorun_frames += 1
	if _autorun_frames > 900:
		print("[autorun] Completed %d frames. Kills: %d, boxes: %d, floor: %d" % [
			_autorun_frames, GameState.kills, GameState.boxes_opened, GameState.floor_number])
		get_tree().quit(0)
		return

	if race_class_screen.visible:
		race_class_screen.debug_pick_random()
		return
	if shop_screen.visible:
		shop_screen.close()
		return
	if guide_screen.visible:
		guide_screen.close()
		return
	if map_screen.visible:
		map_screen.close()
		return
	if achievements_screen.visible:
		achievements_screen.close()
		return
	if game_over_screen.visible:
		game_over_screen.close()
		start_run(CharGenerator.random_character())
		return
	if char_create_screen.visible:
		char_create_screen._on_confirm()
		return

	var actions := ["move_up", "move_down", "move_left", "move_right", "wait", "ability", "attack"]
	var ev := InputEventAction.new()
	ev.action = actions[_autorun_rng.randi_range(0, actions.size() - 1)]
	ev.pressed = true
	Input.parse_input_event(ev)


func _shot_tick() -> void:
	_autorun_frames += 1
	match _autorun_frames:
		44:
			if is_instance_valid(dungeon):
				for e: Entity in dungeon.enemies:
					e.hp = maxi(int(e.max_hp * 0.55), 1)  # show off health bars
		45:
			_capture("gameplay")
		46:
			if is_instance_valid(dungeon):
				dungeon.turn_manager.lock()
			GameState.character.unspent_stat_points = 4
			inventory_screen.allocate_allowed = true
			inventory_screen.open()
		50:
			if GameState.character.inventory.size() > 0:
				inventory_screen._on_inventory_selected(0)
		60:
			_capture("inventory")
		61:
			inventory_screen.close()
			if is_instance_valid(dungeon) and dungeon.shopkeeper != null:
				shop_screen.open_for(dungeon.shopkeeper)
				shop_screen._on_stock_selected(0)
		70:
			_capture("shop")
		71:
			shop_screen.close()
			guide_screen.open(dungeon if is_instance_valid(dungeon) else null)
		80:
			_capture("guide")
		81:
			guide_screen.close()
			if is_instance_valid(dungeon):
				for zone in dungeon.zones_runtime.size():
					dungeon.zone_visited[zone] = true
					dungeon.reveal_zone(zone)
				map_screen.open(dungeon)
		90:
			_capture("map")
		91:
			map_screen.close()
			race_class_screen.open()
		105:
			_capture("race_class")
		106:
			race_class_screen.visible = false
			show_char_create()
		120:
			_capture("char_create")
		122:
			get_tree().quit(0)


func _capture(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://screenshots/%s.png" % shot_name)
	print("[screenshot] saved %s" % shot_name)
