class_name FloorGenerator
extends RefCounted
## Rooms-and-corridors procgen. Rooms are connected in placement order with
## L-shaped corridors, which guarantees full connectivity.


class FloorData:
	var grid: DungeonGrid
	var spawn: Vector2i
	var stairs: Vector2i
	var rooms: Array[Rect2i] = []
	var saferoom := Rect2i()  # zero-size = no saferoom on this floor
	var shop_pos := Vector2i(-1, -1)  # shopkeeper location, (-1,-1) = none
	var enemy_spawns: Array[Vector2i] = []
	var box_spawns: Array = []  # [{ "tier": int, "pos": Vector2i }]
	var zones: Array = []  # [{ "rooms": Array[Rect2i] }] — neighbourhoods
	var zone_of := {}  # Vector2i -> zone index, for every room tile


const MAX_ROOM_ATTEMPTS := 28
const ROOM_MIN := 4
const ROOM_MAX := 9


static func generate(width: int, height: int, floor_num: int, rng: RandomNumberGenerator) -> FloorData:
	var fd := FloorData.new()
	fd.grid = DungeonGrid.new(width, height)

	# 1. Place non-overlapping rooms
	for i in MAX_ROOM_ATTEMPTS:
		var w := rng.randi_range(ROOM_MIN, ROOM_MAX)
		var h := rng.randi_range(ROOM_MIN, ROOM_MAX)
		var x := rng.randi_range(1, width - w - 2)
		var y := rng.randi_range(1, height - h - 2)
		var room := Rect2i(x, y, w, h)
		var padded := room.grow(1)
		var overlaps := false
		for other in fd.rooms:
			if padded.intersects(other):
				overlaps = true
				break
		if not overlaps:
			fd.rooms.append(room)

	# 2. Carve rooms
	for room in fd.rooms:
		for ry in range(room.position.y, room.end.y):
			for rx in range(room.position.x, room.end.x):
				fd.grid.set_tile(Vector2i(rx, ry), DungeonGrid.FLOOR)

	# 3. Connect consecutive room centers with L-corridors
	for i in range(1, fd.rooms.size()):
		var a := fd.rooms[i - 1].get_center()
		var b := fd.rooms[i].get_center()
		if rng.randf() < 0.5:
			_carve_h(fd.grid, a.x, b.x, a.y)
			_carve_v(fd.grid, a.y, b.y, b.x)
		else:
			_carve_v(fd.grid, a.y, b.y, a.x)
			_carve_h(fd.grid, a.x, b.x, b.y)

	# 4. Spawn in room 0; stairs in the room farthest from it
	fd.spawn = fd.rooms[0].get_center()
	var far_room := fd.rooms[0]
	var far_dist := -1.0
	for room in fd.rooms:
		var d := Vector2(room.get_center()).distance_to(Vector2(fd.spawn))
		if d > far_dist:
			far_dist = d
			far_room = room
	fd.stairs = far_room.get_center()
	fd.grid.set_tile(fd.stairs, DungeonGrid.STAIRS)

	# 4b. Saferoom: floor 3 uses the spawn room (the race/class rebrand happens
	# in safety); other floors hide one in a random non-spawn, non-stairs room.
	# NOTE: saferooms are generic safe zones — shops will be a separate entity.
	if floor_num == 3:
		fd.saferoom = fd.rooms[0]
	else:
		var candidates: Array[Rect2i] = []
		for room in fd.rooms:
			if room != fd.rooms[0] and room != far_room:
				candidates.append(room)
		if not candidates.is_empty():
			fd.saferoom = candidates[rng.randi_range(0, candidates.size() - 1)]
	if fd.saferoom.size != Vector2i.ZERO:
		for ry in range(fd.saferoom.position.y, fd.saferoom.end.y):
			for rx in range(fd.saferoom.position.x, fd.saferoom.end.x):
				if fd.grid.get_tile(Vector2i(rx, ry)) == DungeonGrid.FLOOR:
					fd.grid.set_tile(Vector2i(rx, ry), DungeonGrid.SAFE)

	# 4c. Neighbourhoods: cluster rooms around 2-4 spread-out seed rooms
	_build_zones(fd, rng)

	# 5. Enemy + loot box placement on random floor tiles (not room 0, not near spawn)
	var enemy_count := 8 + floor_num * 2
	var taken := { fd.spawn: true, fd.stairs: true }
	for i in enemy_count:
		var pos := _random_floor_tile(fd, rng, taken, 6)
		if pos != Vector2i(-1, -1):
			fd.enemy_spawns.append(pos)
			taken[pos] = true

	var box_count := rng.randi_range(3, 5)
	for i in box_count:
		var pos := _random_floor_tile(fd, rng, taken, 3)
		if pos != Vector2i(-1, -1):
			fd.box_spawns.append({ "tier": _roll_box_tier(floor_num, rng), "pos": pos })
			taken[pos] = true

	# Shopkeeper: separate entity from the saferoom, out on the floor proper
	fd.shop_pos = _random_floor_tile(fd, rng, taken, 4)
	if fd.shop_pos != Vector2i(-1, -1):
		taken[fd.shop_pos] = true

	return fd


## Neighbourhoods: farthest-point sampling picks spread-out seed rooms, then
## every room joins its nearest seed. Guarantees 2-4 contiguous-ish districts.
static func _build_zones(fd: FloorData, rng: RandomNumberGenerator) -> void:
	var k := clampi(fd.rooms.size() / 4, 2, 4)
	var seeds: Array[int] = [rng.randi_range(0, fd.rooms.size() - 1)]
	while seeds.size() < k:
		var best := -1
		var best_dist := -1.0
		for i in fd.rooms.size():
			if seeds.has(i):
				continue
			var min_dist := INF
			for s in seeds:
				min_dist = minf(min_dist, Vector2(fd.rooms[i].get_center()).distance_to(Vector2(fd.rooms[s].get_center())))
			if min_dist > best_dist:
				best_dist = min_dist
				best = i
		seeds.append(best)

	for i in k:
		fd.zones.append({ "rooms": [] as Array[Rect2i] })
	for i in fd.rooms.size():
		var room := fd.rooms[i]
		var nearest := 0
		var nearest_dist := INF
		for s in seeds.size():
			var d := Vector2(room.get_center()).distance_to(Vector2(fd.rooms[seeds[s]].get_center()))
			if d < nearest_dist:
				nearest_dist = d
				nearest = s
		fd.zones[nearest]["rooms"].append(room)
		for ry in range(room.position.y, room.end.y):
			for rx in range(room.position.x, room.end.x):
				fd.zone_of[Vector2i(rx, ry)] = nearest


## Box tiers: 0 bronze, 1 silver, 2 gold, 3 platinum. Weights shift with depth.
static func _roll_box_tier(floor_num: int, rng: RandomNumberGenerator) -> int:
	var roll := rng.randf() + (floor_num - 1) * 0.15
	if roll > 1.15:
		return 3
	elif roll > 0.95:
		return 2
	elif roll > 0.65:
		return 1
	return 0


static func _random_floor_tile(fd: FloorData, rng: RandomNumberGenerator, taken: Dictionary, min_spawn_dist: int) -> Vector2i:
	for attempt in 50:
		var room := fd.rooms[rng.randi_range(1, fd.rooms.size() - 1)] if fd.rooms.size() > 1 else fd.rooms[0]
		var pos := Vector2i(
			rng.randi_range(room.position.x, room.end.x - 1),
			rng.randi_range(room.position.y, room.end.y - 1)
		)
		if taken.has(pos):
			continue
		if fd.grid.get_tile(pos) != DungeonGrid.FLOOR:
			continue
		if Vector2(pos).distance_to(Vector2(fd.spawn)) < min_spawn_dist:
			continue
		return pos
	return Vector2i(-1, -1)


static func _carve_h(grid: DungeonGrid, x1: int, x2: int, y: int) -> void:
	for x in range(mini(x1, x2), maxi(x1, x2) + 1):
		if grid.get_tile(Vector2i(x, y)) == DungeonGrid.WALL:
			grid.set_tile(Vector2i(x, y), DungeonGrid.FLOOR)


static func _carve_v(grid: DungeonGrid, y1: int, y2: int, x: int) -> void:
	for y in range(mini(y1, y2), maxi(y1, y2) + 1):
		if grid.get_tile(Vector2i(x, y)) == DungeonGrid.WALL:
			grid.set_tile(Vector2i(x, y), DungeonGrid.FLOOR)
