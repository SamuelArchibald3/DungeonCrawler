class_name Entity
extends Node2D
## Generic grid actor: the player and every enemy. Renders as a glyph label.
## grid_pos is the truth; the visual position tweens toward it cosmetically.

const TILE := 16
const MOVE_TWEEN_TIME := 0.08

static var _mono_font: SystemFont

var grid_pos: Vector2i
var glyph := "?"
var color := Color.WHITE
var is_player := false

## Enemy-only fields (null/unused for the player)
var enemy_def: EnemyDef
var hp := 0
var max_hp := 0
var xp_value := 0
var turn_counter := 0
var is_boss := false
var boss_name := ""
var zone_index := -1
var glyph_size := 13

var _label: Label
var _tween: Tween


static func make(glyph_: String, color_: Color, pos: Vector2i) -> Entity:
	var e := Entity.new()
	e.glyph = glyph_
	e.color = color_
	e.grid_pos = pos
	e.position = Vector2(pos * TILE)
	return e


static func make_enemy(def: EnemyDef, pos: Vector2i, floor_num: int) -> Entity:
	var e := make(def.glyph, def.color, pos)
	e.enemy_def = def
	# Per-floor scaling beyond the enemy's first floor: tougher and worth more
	e.max_hp = def.max_hp + (floor_num - def.min_floor) * 3
	e.hp = e.max_hp
	e.xp_value = def.xp + (floor_num - def.min_floor) * 2
	return e


## Neighbourhood boss: an upsized local with a name and a grudge.
static func make_boss(def: EnemyDef, pos: Vector2i, floor_num: int, name_: String, zone: int) -> Entity:
	var e := make_enemy(def, pos, floor_num)
	e.is_boss = true
	e.boss_name = name_
	e.zone_index = zone
	e.max_hp *= 4
	e.hp = e.max_hp
	e.xp_value *= 5
	e.color = Color(1.0, 0.4, 0.35)
	e.glyph_size = 16
	return e


func _ready() -> void:
	if _mono_font == null:
		_mono_font = SystemFont.new()
		_mono_font.font_names = PackedStringArray(["Consolas", "Courier New"])
	_label = Label.new()
	_label.text = glyph
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", _mono_font)
	_label.add_theme_font_size_override("font_size", glyph_size)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_constant_override("outline_size", 3)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(_label)
	_center_label.call_deferred()


func _center_label() -> void:
	var ms := _label.get_combined_minimum_size()
	_label.size = ms
	_label.position = (Vector2(TILE, TILE) - ms) / 2.0


func set_grid_pos(p: Vector2i, animate := true) -> void:
	grid_pos = p
	var target := Vector2(p * TILE)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if animate and is_inside_tree():
		_tween = create_tween()
		_tween.tween_property(self, "position", target, MOVE_TWEEN_TIME)
	else:
		position = target


## Cosmetic half-step lunge for attacks.
func bump_toward(dir: Vector2i) -> void:
	if not is_inside_tree():
		return
	var home := Vector2(grid_pos * TILE)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", home + Vector2(dir * TILE) * 0.4, 0.05)
	_tween.tween_property(self, "position", home, 0.07)


func display_name() -> String:
	if is_player:
		return GameState.character.char_name
	if boss_name != "":
		return boss_name
	return enemy_def.display_name if enemy_def != null else "???"
