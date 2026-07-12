class_name Npc
extends Node2D
## Base for friendly bump-to-interact NPCs (shopkeeper, guide).
## Occupies a grid tile; enemies never target NPCs.

const TILE := Entity.TILE

static var _mono_font: SystemFont

var grid_pos: Vector2i
var glyph := "?"
var color := Color.WHITE
var dungeon: Dungeon


func _ready() -> void:
	if _mono_font == null:
		_mono_font = SystemFont.new()
		_mono_font.font_names = PackedStringArray(["Consolas", "Courier New"])
	var label := Label.new()
	label.text = glyph
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _mono_font)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(label)
	_center_label.call_deferred(label)


func _center_label(label: Label) -> void:
	var ms := label.get_combined_minimum_size()
	label.size = ms
	label.position = (Vector2(TILE, TILE) - ms) / 2.0


## Override in subclasses.
func on_bumped() -> void:
	pass
