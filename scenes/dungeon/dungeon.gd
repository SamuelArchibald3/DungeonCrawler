class_name Dungeon
extends Node2D
## One dungeon floor: paints the TileMapLayer from FloorData, spawns
## entities, owns the TurnManager. Freed and rebuilt on descend.

signal descend_requested
signal race_class_requested
signal shop_requested(shopkeeper: Shopkeeper)
signal guide_requested

const TILE := Entity.TILE
const FLOOR_W := 192
const FLOOR_H := 128

## Subtle per-zone floor tints (atlas 4..7) and their bright map equivalents
const ZONE_FLOOR_COLORS: Array[Color] = [
	Color(0.36, 0.28, 0.30), Color(0.28, 0.34, 0.30),
	Color(0.28, 0.30, 0.38), Color(0.36, 0.33, 0.27),
]
const ZONE_MAP_COLORS: Array[Color] = [
	Color(0.75, 0.45, 0.5), Color(0.45, 0.7, 0.5),
	Color(0.45, 0.55, 0.85), Color(0.8, 0.7, 0.4),
]

var grid: DungeonGrid
var floor_data: FloorGenerator.FloorData
var player: Entity
var enemies: Array[Entity] = []
var turn_manager: TurnManager
var shopkeeper: Shopkeeper
var guide: Guide
var borough_boss: Entity

## Neighbourhoods: aligned with floor_data.zones by index
## Crawler entities currently instantiated on this floor (player + real-tier
## NPCs). Enemy AI targets the nearest of these.
var real_crawler_entities: Array[Entity] = []

var zones_runtime: Array = []  # [{ "name": String, "def": EnemyDef, "boss": Entity }]
var zone_visited := {}  # zone index -> true
var explored := {}  # Vector2i -> true (fog-of-war for the map screen)

var _tile_layer: TileMapLayer
var _entities_root: Node2D
var _enemy_defs: Array[EnemyDef] = EnemyDef.all()


func _ready() -> void:
	var floor_num: int = GameState.floor_number
	floor_data = FloorGenerator.generate(FLOOR_W, FLOOR_H, floor_num, GameState.rng)
	grid = floor_data.grid

	_build_tile_layer()
	_entities_root = Node2D.new()
	add_child(_entities_root)

	_assign_zones(floor_num)
	_spawn_stairs_marker()
	_spawn_loot_boxes()
	_spawn_enemies(floor_num)
	_spawn_bosses(floor_num)
	_spawn_borough_boss(floor_num)
	if borough_boss == null:
		unlock_stairs()  # no warden, no seal
	_spawn_shopkeeper(floor_num)
	_spawn_guide()
	_spawn_player()
	reveal_around(floor_data.spawn)
	var spawn_zone := zone_at(floor_data.spawn)
	if spawn_zone != -1:
		zone_visited[spawn_zone] = true  # no announcement for home turf
	Crawlers.assign_floor_positions(floor_data)

	turn_manager = TurnManager.new()
	turn_manager.dungeon = self
	add_child(turn_manager)

	# Spawning inside a saferoom (floor 3): announce it instead of on-entry
	if grid.is_safe(player.grid_pos):
		turn_manager.saferoom_announced = true
		Events.msg.bind("You awaken in a Safe Room. Take a breath. The dungeon will wait. Briefly.", &"system").call_deferred()

	# Deferred so main has connected race_class_requested (it connects after add_child)
	turn_manager.maybe_trigger_race_class.call_deferred()


func _build_tile_layer() -> void:
	# Runtime tileset: wall / floor / stairs / safe / 4 zone floors / locked stairs.
	var img := Image.create(TILE * 9, TILE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE, TILE), Color(0.13, 0.11, 0.16))          # wall
	img.fill_rect(Rect2i(TILE, 0, TILE, TILE), Color(0.32, 0.29, 0.36))       # floor
	img.fill_rect(Rect2i(TILE, 0, TILE, 1), Color(0.27, 0.24, 0.31))          # floor grid line
	img.fill_rect(Rect2i(TILE, 0, 1, TILE), Color(0.27, 0.24, 0.31))
	img.fill_rect(Rect2i(TILE * 2, 0, TILE, TILE), Color(0.32, 0.29, 0.36))   # stairs base
	img.fill_rect(Rect2i(TILE * 2 + 3, 3, TILE - 6, TILE - 6), Color(0.85, 0.68, 0.25))
	img.fill_rect(Rect2i(TILE * 3, 0, TILE, TILE), Color(0.16, 0.34, 0.36))   # safe floor
	img.fill_rect(Rect2i(TILE * 3, 0, TILE, 1), Color(0.2, 0.42, 0.44))       # safe grid line
	img.fill_rect(Rect2i(TILE * 3, 0, 1, TILE), Color(0.2, 0.42, 0.44))
	for z in 4:  # zone-tinted floor variants at atlas 4..7
		var zc := ZONE_FLOOR_COLORS[z]
		img.fill_rect(Rect2i(TILE * (4 + z), 0, TILE, TILE), zc)
		img.fill_rect(Rect2i(TILE * (4 + z), 0, TILE, 1), zc.darkened(0.15))
		img.fill_rect(Rect2i(TILE * (4 + z), 0, 1, TILE), zc.darkened(0.15))
	img.fill_rect(Rect2i(TILE * 8, 0, TILE, TILE), Color(0.32, 0.29, 0.36))    # locked stairs base
	img.fill_rect(Rect2i(TILE * 8 + 3, 3, TILE - 6, TILE - 6), Color(0.6, 0.18, 0.22))

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in 9:
		src.create_tile(Vector2i(i, 0))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)

	_tile_layer = TileMapLayer.new()
	_tile_layer.tile_set = ts
	add_child(_tile_layer)

	for y in grid.height:
		for x in grid.width:
			var pos := Vector2i(x, y)
			var t := grid.get_tile(pos)
			var atlas_x := t
			if t == DungeonGrid.FLOOR:
				var zone: int = floor_data.zone_of.get(pos, -1)
				if zone != -1:
					atlas_x = 4 + (zone % 4)
			elif t == DungeonGrid.LOCKED_STAIRS:
				atlas_x = 8
			_tile_layer.set_cell(pos, 0, Vector2i(atlas_x, 0))


func _spawn_stairs_marker() -> void:
	var marker := Entity.make(">", Color(0.2, 0.15, 0.05), floor_data.stairs)
	_entities_root.add_child(marker)  # purely visual; stairs is a tile
	if floor_data.stairs_free != Vector2i(-1, -1):
		var free_marker := Entity.make(">", Color(0.2, 0.15, 0.05), floor_data.stairs_free)
		_entities_root.add_child(free_marker)


func _spawn_player() -> void:
	player = Entity.make("@", Color.WHITE, floor_data.spawn)
	player.is_player = true
	player.sheet = GameState.character
	grid.place_entity(player, floor_data.spawn)
	_entities_root.add_child(player)
	real_crawler_entities.append(player)

	var cam := Camera2D.new()
	cam.zoom = Vector2(2.0, 2.0)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.offset = Vector2(TILE / 2.0, TILE / 2.0)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = grid.width * TILE
	cam.limit_bottom = grid.height * TILE
	player.add_child(cam)


## Each neighbourhood gets one enemy type, weighted toward deep-floor natives.
func _assign_zones(floor_num: int) -> void:
	var available: Array[EnemyDef] = []
	for def in _enemy_defs:
		if def.min_floor <= floor_num:
			available.append(def)
	var order := range(available.size())
	order.shuffle()
	for i in floor_data.zones.size():
		var def: EnemyDef = available[order[i % available.size()]]
		zones_runtime.append({
			"name": Flavor.zone_name(def.id, GameState.rng),
			"def": def,
			"boss": null,
		})


func zone_at(pos: Vector2i) -> int:
	return floor_data.zone_of.get(pos, -1)


func zone_name(index: int) -> String:
	return zones_runtime[index]["name"] if index >= 0 and index < zones_runtime.size() else "???"


func _spawn_enemies(floor_num: int) -> void:
	for pos in floor_data.enemy_spawns:
		var zone := zone_at(pos)
		var def: EnemyDef = zones_runtime[zone]["def"] if zone != -1 else _enemy_defs[0]
		var enemy := Entity.make_enemy(def, pos, floor_num)
		grid.place_entity(enemy, pos)
		enemies.append(enemy)
		_entities_root.add_child(enemy)


## One boss per neighbourhood, in its largest room (never the saferoom).
func _spawn_bosses(floor_num: int) -> void:
	for zone in floor_data.zones.size():
		var rooms: Array = floor_data.zones[zone]["rooms"]
		var best := Rect2i()
		for room: Rect2i in rooms:
			if room == floor_data.saferoom or room == floor_data.shop_room \
					or room == floor_data.rooms[0] \
					or room.has_point(floor_data.stairs):
				continue  # spawn room stays empty; stairs room belongs to the borough boss
			if room.get_area() > best.get_area():
				best = room
		if best.size == Vector2i.ZERO:
			continue
		var def: EnemyDef = zones_runtime[zone]["def"]
		var center := best.get_center()
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var pos: Vector2i = center + offset
			if pos != floor_data.spawn and grid.is_open(pos) \
					and grid.get_tile(pos) == DungeonGrid.FLOOR:
				var boss := Entity.make_boss(def, pos, floor_num, Flavor.boss_name(def.id), zone)
				grid.place_entity(boss, pos)
				enemies.append(boss)
				zones_runtime[zone]["boss"] = boss
				_entities_root.add_child(boss)
				break


## One borough boss per floor, holding the stairs room: the deepest native
## enemy type, upscaled well past any neighbourhood boss.
func _spawn_borough_boss(floor_num: int) -> void:
	var stairs_room := Rect2i()
	for room in floor_data.rooms:
		if room.has_point(floor_data.stairs):
			stairs_room = room
			break
	if stairs_room.size == Vector2i.ZERO:
		return
	var best_def: EnemyDef = null
	for def in _enemy_defs:
		if def.min_floor <= floor_num and (best_def == null or def.min_floor > best_def.min_floor):
			best_def = def
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var pos := floor_data.stairs + Vector2i(dx, dy)
				if stairs_room.has_point(pos) and grid.is_open(pos) \
						and grid.get_tile(pos) == DungeonGrid.FLOOR:
					borough_boss = Entity.make_borough_boss(
						best_def, pos, floor_num, Flavor.borough_boss_name(GameState.rng))
					grid.place_entity(borough_boss, pos)
					enemies.append(borough_boss)
					_entities_root.add_child(borough_boss)
					Events.msg.bind("%s has sealed this floor's express stairwell. A public stairwell exists elsewhere. Probably." % borough_boss.boss_name, &"system").call_deferred()
					return


## Unseals the borough boss's stairwell (on his death, or if he never spawned).
func unlock_stairs() -> void:
	if grid.get_tile(floor_data.stairs) != DungeonGrid.LOCKED_STAIRS:
		return
	grid.set_tile(floor_data.stairs, DungeonGrid.STAIRS)
	_tile_layer.set_cell(floor_data.stairs, 0, Vector2i(DungeonGrid.STAIRS, 0))


## --- Fog of war for the map screen ---

func reveal_around(pos: Vector2i, radius: int = 4) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var p := pos + Vector2i(dx, dy)
			if grid.in_bounds(p):
				explored[p] = true


func reveal_all() -> void:
	for y in grid.height:
		for x in grid.width:
			explored[Vector2i(x, y)] = true


func reveal_zone(zone: int) -> void:
	for room: Rect2i in floor_data.zones[zone]["rooms"]:
		for ry in range(room.position.y - 1, room.end.y + 1):
			for rx in range(room.position.x - 1, room.end.x + 1):
				var p := Vector2i(rx, ry)
				if grid.in_bounds(p):
					explored[p] = true


func _spawn_loot_boxes() -> void:
	for spawn in floor_data.box_spawns:
		spawn_loot_box(spawn["tier"], spawn["pos"])


func _spawn_shopkeeper(floor_num: int) -> void:
	var pos := floor_data.shop_pos
	if pos == Vector2i(-1, -1) or not grid.is_open(pos):
		return
	shopkeeper = Shopkeeper.make(pos, floor_num)
	shopkeeper.dungeon = self
	grid.place_entity(shopkeeper, pos)
	_entities_root.add_child(shopkeeper)


func _spawn_guide() -> void:
	if floor_data.saferoom.size == Vector2i.ZERO:
		return
	var center := floor_data.saferoom.get_center()
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1)]:
		var pos: Vector2i = center + offset
		if pos != floor_data.spawn and grid.is_safe(pos) and grid.is_open(pos):
			guide = Guide.make(pos)
			guide.dungeon = self
			grid.place_entity(guide, pos)
			_entities_root.add_child(guide)
			return


## Cosmetic ranged-attack projectile: a small dot zipping between tiles.
func show_projectile(from: Vector2i, to: Vector2i, color := Color(0.65, 0.9, 0.3)) -> void:
	var dot := ColorRect.new()
	dot.color = color
	dot.size = Vector2(4, 4)
	dot.position = Vector2(from * TILE) + Vector2(6, 6)
	_entities_root.add_child(dot)
	var tween := dot.create_tween()
	tween.tween_property(dot, "position", Vector2(to * TILE) + Vector2(6, 6), 0.15)
	tween.tween_callback(dot.queue_free)


func spawn_loot_box(tier: int, pos: Vector2i) -> void:
	if not grid.is_open(pos):
		return
	var box := LootBox.make(tier, pos)
	box.dungeon = self
	grid.place_entity(box, pos)
	_entities_root.add_child(box)
