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
		var fd = FloorGeneratorScript.generate(68, 44, floor_num, rng)

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

		if floor_num == 3 and fd.grid.get_tile(fd.spawn) != DungeonGridScript.SAFE:
			print("FAIL seed %d: floor 3 spawn is not inside a saferoom" % seed_value)
			failures += 1

		if fd.zones.size() < 2 or fd.zones.size() > 4:
			print("FAIL seed %d: zone count %d out of range" % [seed_value, fd.zones.size()])
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
