class_name Entity
extends Node2D
## Generic grid actor: the player and every enemy. Renders as a glyph label.
## grid_pos is the truth; the visual position tweens toward it cosmetically.

const TILE := 16
const MOVE_TWEEN_TIME := 0.08          # turn-based: quick hop
const REALTIME_PLAYER_GLIDE := 0.26    # realtime: glide matching action cadence
const REALTIME_ENEMY_GLIDE := 0.3

static var _mono_font: SystemFont

const FACING_DOT_POS := {
	Vector2i.UP: Vector2(6.5, -2), Vector2i.DOWN: Vector2(6.5, 15),
	Vector2i.LEFT: Vector2(-2, 6.5), Vector2i.RIGHT: Vector2(15, 6.5),
}

var grid_pos: Vector2i
var glyph := "?"
var color := Color.WHITE
var is_player := false
var facing := Vector2i.DOWN

## Enemy-only fields (null/unused for the player)
var enemy_def: EnemyDef
var hp := 0:
	set(value):
		hp = value
		_update_health_bar()
var max_hp := 0
var xp_value := 0
var turn_counter := 0
var is_boss := false
var is_borough := false
var boss_name := ""
var zone_index := -1
var glyph_size := 13
var telegraphs_attacks := false
var winding_up := false
var windup_target := Vector2i.ZERO

var _label: Label
var _tween: Tween
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _telegraph_mark: Label
var _facing_dot: ColorRect


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
	e.telegraphs_attacks = def.telegraphs
	# Per-floor scaling beyond the enemy's first floor: tougher and worth more
	e.max_hp = def.max_hp + (floor_num - def.min_floor) * 3
	e.hp = e.max_hp
	e.xp_value = def.xp + (floor_num - def.min_floor) * 2
	return e


## Neighbourhood boss: an upsized local with a name and a grudge.
static func make_boss(def: EnemyDef, pos: Vector2i, floor_num: int, name_: String, zone: int) -> Entity:
	var e := make_enemy(def, pos, floor_num)
	e.is_boss = true
	e.telegraphs_attacks = true  # boss hits are always big enough to see coming
	e.boss_name = name_
	e.zone_index = zone
	e.max_hp *= 4
	e.hp = e.max_hp
	e.xp_value *= 5
	e.color = Color(1.0, 0.4, 0.35)
	e.glyph_size = 16
	return e


## Borough boss: one per floor, guards the stairwell. Stronger than any
## neighbourhood boss; rewards to match.
static func make_borough_boss(def: EnemyDef, pos: Vector2i, floor_num: int, name_: String) -> Entity:
	var e := make_boss(def, pos, floor_num, name_, -1)
	e.is_borough = true
	e.max_hp *= 2   # 8x base
	e.hp = e.max_hp
	e.xp_value *= 2  # 10x base
	e.color = Color(1.0, 0.3, 0.55)
	e.glyph_size = 18
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

	if is_player:
		_facing_dot = ColorRect.new()
		_facing_dot.color = Color(0.95, 0.85, 0.4)
		_facing_dot.size = Vector2(3, 3)
		add_child(_facing_dot)
		set_facing(facing)

	if enemy_def != null:
		_bar_bg = ColorRect.new()
		_bar_bg.color = Color(0, 0, 0, 0.7)
		_bar_bg.position = Vector2(1, -4)
		_bar_bg.size = Vector2(TILE - 2, 3)
		add_child(_bar_bg)
		_bar_fill = ColorRect.new()
		_bar_fill.position = Vector2(1, -4)
		_bar_fill.size = Vector2(TILE - 2, 3)
		add_child(_bar_fill)
		_update_health_bar()


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
		var duration := MOVE_TWEEN_TIME
		if GameState.realtime_mode:
			duration = REALTIME_PLAYER_GLIDE if is_player else REALTIME_ENEMY_GLIDE
		_tween = create_tween()
		_tween.tween_property(self, "position", target, duration)
	else:
		position = target


func set_facing(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	facing = dir
	if _facing_dot != null and FACING_DOT_POS.has(dir):
		_facing_dot.position = FACING_DOT_POS[dir]


## Attack visual: lunge plus a slash arc sweeping across the target tile.
func play_attack_slash(dir: Vector2i) -> void:
	bump_toward(dir)
	if not is_inside_tree():
		return
	var slash := ColorRect.new()
	slash.color = Color(1, 0.95, 0.7, 0.9)
	slash.size = Vector2(14, 2)
	slash.pivot_offset = Vector2(1, 1)
	slash.position = Vector2((grid_pos + dir) * TILE) + Vector2(TILE / 2.0, TILE / 2.0)
	var base_angle := Vector2(dir).angle()
	slash.rotation = base_angle - 0.9
	get_parent().add_child(slash)
	var tween := slash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "rotation", base_angle + 0.9, 0.12)
	tween.tween_property(slash, "modulate:a", 0.0, 0.14)
	tween.chain().tween_callback(slash.queue_free)


## Brief white flash when taking a hit.
func flash_hit() -> void:
	if _label == null or not is_inside_tree():
		return
	_label.modulate = Color(4, 4, 4)
	create_tween().tween_property(_label, "modulate", Color.WHITE, 0.15)


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


## Health bar: hidden at full HP, green -> red as HP falls.
func _update_health_bar() -> void:
	if _bar_fill == null:
		return
	var damaged := hp < max_hp
	_bar_bg.visible = damaged
	_bar_fill.visible = damaged
	var fraction := clampf(float(hp) / maxf(float(max_hp), 1.0), 0.0, 1.0)
	_bar_fill.size.x = (TILE - 2) * fraction
	_bar_fill.color = Color(0.9, 0.2, 0.15).lerp(Color(0.25, 0.8, 0.25), fraction)


## Windup warning: "!" over the glyph and a hot flash while telegraphing.
func set_telegraphing(active: bool) -> void:
	if active and _telegraph_mark == null:
		_telegraph_mark = Label.new()
		_telegraph_mark.text = "!"
		_telegraph_mark.position = Vector2(TILE - 6, -10)
		_telegraph_mark.add_theme_font_size_override("font_size", 13)
		_telegraph_mark.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		_telegraph_mark.add_theme_constant_override("outline_size", 3)
		_telegraph_mark.add_theme_color_override("font_outline_color", Color(0.5, 0.1, 0.05))
		add_child(_telegraph_mark)
	if _telegraph_mark != null:
		_telegraph_mark.visible = active
	if _label != null:
		_label.add_theme_color_override("font_color", Color(1, 0.95, 0.55) if active else color)


func health_bar_visible() -> bool:
	return _bar_fill != null and _bar_fill.visible


func health_bar_color() -> Color:
	return _bar_fill.color if _bar_fill != null else Color()


func display_name() -> String:
	if is_player:
		return GameState.character.char_name
	if boss_name != "":
		return boss_name
	return enemy_def.display_name if enemy_def != null else "???"
