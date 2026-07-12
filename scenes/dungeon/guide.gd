class_name Guide
extends Npc
## The saferoom guide: a very tired Bopca who explains the dungeon.


static func make(pos: Vector2i) -> Guide:
	var g := Guide.new()
	g.grid_pos = pos
	g.position = Vector2(pos * TILE)
	g.glyph = "?"
	g.color = Color(0.45, 0.85, 0.9)
	return g


func on_bumped() -> void:
	dungeon.guide_requested.emit()
