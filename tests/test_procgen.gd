extends SceneTree
## Headless procgen test: 100 seeded floors must be fully connected
## (spawn -> stairs reachable), with all spawns on walkable tiles.
## Run: godot --headless --path . --script res://tests/test_procgen.gd

const FloorGeneratorScript := preload("res://scripts/floor_generator.gd")
const DungeonGridScript := preload("res://scripts/dungeon_grid.gd")


func _init() -> void:
	var failures := 0
	for seed_value in 100:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var floor_num := (seed_value % 4) + 1
		var fd = FloorGeneratorScript.generate(192, 128, floor_num, rng)

		if not fd.grid.is_walkable(fd.spawn):
			print("FAIL seed %d: spawn not walkable" % seed_value)
			failures += 1
			continue
		if not fd.grid.is_walkable(fd.stairs):
			print("FAIL seed %d: stairs not walkable" % seed_value)
			failures += 1
			continue
		if not _reachable(fd.grid, fd.spawn, fd.stairs):
			print("FAIL seed %d: stairs unreachable from spawn" % seed_value)
			failures += 1
			continue

		# Dual stairwells: boss stairs sealed, public stairs active and reachable
		if fd.stairs_free == Vector2i(-1, -1):
			if fd.grid.get_tile(fd.stairs) != DungeonGridScript.STAIRS:
				print("FAIL seed %d: no public stairwell and boss stairs not active" % seed_value)
				failures += 1
		else:
			if fd.grid.get_tile(fd.stairs) != DungeonGridScript.LOCKED_STAIRS:
				print("FAIL seed %d: boss stairwell not sealed" % seed_value)
				failures += 1
			if fd.grid.get_tile(fd.stairs_free) != DungeonGridScript.STAIRS \
					or not _reachable(fd.grid, fd.spawn, fd.stairs_free):
				print("FAIL seed %d: public stairwell missing or unreachable" % seed_value)
				failures += 1
			if fd.saferoom.has_point(fd.stairs_free) or fd.shop_room.has_point(fd.stairs_free):
				print("FAIL seed %d: public stairwell inside saferoom/shop room" % seed_value)
				failures += 1

		if floor_num == 3 and fd.grid.get_tile(fd.spawn) != DungeonGridScript.SAFE:
			print("FAIL seed %d: floor 3 spawn is not inside a saferoom" % seed_value)
			failures += 1

		if fd.zones.size() < 4 or fd.zones.size() > 8:
			print("FAIL seed %d: zone count %d out of range" % [seed_value, fd.zones.size()])
			failures += 1

		# Cohort invariants: 99 unique crawler spawns on plain floor tiles
		# outside the spawn/shop/safe rooms; room graph fully connected
		if fd.crawler_spawns.size() != 99:
			print("FAIL seed %d: crawler spawn count %d != 99" % [seed_value, fd.crawler_spawns.size()])
			failures += 1
		var seen_crawler := {}
		for pos in fd.crawler_spawns:
			if fd.grid.get_tile(pos) != DungeonGridScript.FLOOR or seen_crawler.has(pos) \
					or fd.rooms[0].has_point(pos) or fd.shop_room.has_point(pos) \
					or fd.saferoom.has_point(pos):
				print("FAIL seed %d: bad crawler spawn at %s" % [seed_value, pos])
				failures += 1
				break
			seen_crawler[pos] = true
		var visited_rooms := { 0: true }
		var room_queue := [0]
		while not room_queue.is_empty():
			var current_room: int = room_queue.pop_front()
			for neighbor in fd.room_graph[current_room]:
				if not visited_rooms.has(neighbor):
					visited_rooms[neighbor] = true
					room_queue.append(neighbor)
		if visited_rooms.size() != fd.rooms.size():
			print("FAIL seed %d: room graph disconnected (%d/%d)" % [seed_value, visited_rooms.size(), fd.rooms.size()])
			failures += 1
		var expected_room_tiles := 0
		for room in fd.rooms:
			expected_room_tiles += room.get_area()
		if fd.room_of.size() != expected_room_tiles:
			print("FAIL seed %d: room_of incomplete (%d/%d)" % [seed_value, fd.room_of.size(), expected_room_tiles])
			failures += 1
		var zoned := 0
		for zone_info in fd.zones:
			zoned += zone_info["rooms"].size()
		if zoned != fd.rooms.size():
			print("FAIL seed %d: %d/%d rooms zoned" % [seed_value, zoned, fd.rooms.size()])
			failures += 1
		for pos in fd.enemy_spawns:
			if not fd.zone_of.has(pos):
				print("FAIL seed %d: enemy spawn outside all zones" % seed_value)
				failures += 1
				break

		# The spawn room must be empty: no enemies or boxes generate inside it
		var spawn_room: Rect2i = fd.rooms[0]
		for pos in fd.enemy_spawns:
			if spawn_room.has_point(pos):
				print("FAIL seed %d: enemy spawned in the spawn room" % seed_value)
				failures += 1
				break
		for spawn in fd.box_spawns:
			if spawn_room.has_point(spawn["pos"]):
				print("FAIL seed %d: loot box spawned in the spawn room" % seed_value)
				failures += 1
				break

		var seen := {}
		var bad_placement := false
		for pos in fd.enemy_spawns:
			if fd.grid.get_tile(pos) != DungeonGridScript.FLOOR or seen.has(pos):
				bad_placement = true
			seen[pos] = true
		for spawn in fd.box_spawns:
			if fd.grid.get_tile(spawn["pos"]) != DungeonGridScript.FLOOR or seen.has(spawn["pos"]):
				bad_placement = true
			seen[spawn["pos"]] = true
		if fd.shop_pos != Vector2i(-1, -1):
			if fd.grid.get_tile(fd.shop_pos) != DungeonGridScript.FLOOR or seen.has(fd.shop_pos):
				bad_placement = true
			seen[fd.shop_pos] = true
			# Bopca must be strictly interior — a perimeter tile could plug a doorway
			if not fd.shop_room.grow(-1).has_point(fd.shop_pos):
				print("FAIL seed %d: shopkeeper on shop room perimeter" % seed_value)
				failures += 1
			# Nothing else spawns in the shop room; it's never a special room
			for pos in fd.enemy_spawns:
				if fd.shop_room.has_point(pos):
					print("FAIL seed %d: enemy spawned in shop room" % seed_value)
					failures += 1
					break
			for spawn in fd.box_spawns:
				if fd.shop_room.has_point(spawn["pos"]):
					print("FAIL seed %d: loot box spawned in shop room" % seed_value)
					failures += 1
					break
			if fd.shop_room == fd.rooms[0] or fd.shop_room == fd.saferoom \
					or fd.shop_room.has_point(fd.stairs):
				print("FAIL seed %d: shop room overlaps spawn/saferoom/stairs" % seed_value)
				failures += 1
		if bad_placement:
			print("FAIL seed %d: bad/overlapping/saferoom entity placement" % seed_value)
			failures += 1

	if failures == 0:
		print("PASS: 100/100 floors connected and validly populated")
	else:
		print("FAILED: %d/100 floors had problems" % failures)
	quit(1 if failures > 0 else 0)


func _reachable(grid, from: Vector2i, to: Vector2i) -> bool:
	var queue: Array[Vector2i] = [from]
	var visited := { from: true }
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			return true
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = current + dir
			if grid.is_walkable(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return false
