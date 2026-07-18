class_name DungeonGrid
extends RefCounted
## Single source of spatial truth: tile types + entity occupancy.
## All movement/combat queries go through this; no physics anywhere.

enum { WALL, FLOOR, STAIRS, SAFE, LOCKED_STAIRS }

var width: int
var height: int
var tiles: PackedInt32Array
var occupancy: Dictionary = {}  # Vector2i -> Object (Entity or LootBox)


func _init(w: int, h: int) -> void:
	width = w
	height = h
	tiles.resize(w * h)  # zero-filled = all WALL


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


func get_tile(p: Vector2i) -> int:
	return tiles[p.y * width + p.x]


func set_tile(p: Vector2i, t: int) -> void:
	tiles[p.y * width + p.x] = t


func is_walkable(p: Vector2i) -> bool:
	return in_bounds(p) and get_tile(p) != WALL


## Saferoom tile: enemies won't enter, no crush damage, HP regen.
func is_safe(p: Vector2i) -> bool:
	return in_bounds(p) and get_tile(p) == SAFE


## Walkable and unoccupied.
func is_open(p: Vector2i) -> bool:
	return is_walkable(p) and not occupancy.has(p)


## Bresenham line: true when no WALL sits between the endpoints (exclusive).
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx + dy
	var p := from
	while true:
		if p != from and p != to and get_tile(p) == WALL:
			return false
		if p == to:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return true


func entity_at(p: Vector2i) -> Object:
	var e: Object = occupancy.get(p)
	# Self-heal: an entity freed without deregistering must never crash queries
	if e != null and not is_instance_valid(e):
		occupancy.erase(p)
		return null
	return e


func place_entity(e: Object, p: Vector2i) -> void:
	occupancy[p] = e


func move_entity(e: Object, from: Vector2i, to: Vector2i) -> void:
	if occupancy.get(from) == e:
		occupancy.erase(from)
	occupancy[to] = e


func remove_entity(p: Vector2i) -> void:
	occupancy.erase(p)
