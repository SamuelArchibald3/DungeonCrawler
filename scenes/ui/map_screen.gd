class_name MapScreen
extends Control
## Fog-of-war floor map (toggle M). Shows explored tiles, zone colors,
## saferoom, stairs, shopkeeper, living bosses, and you. Killing a
## neighbourhood boss reveals its whole district.

signal closed

var dungeon: Dungeon
var _canvas: Control
var _legend: RichTextLabel


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.text = "SPONSORED SURVEY MAP — accuracy not guaranteed, refunds unavailable"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_canvas = Control.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_map)
	vbox.add_child(_canvas)

	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(_legend)


func open(dungeon_: Dungeon) -> void:
	dungeon = dungeon_
	visible = true
	_build_legend()
	_canvas.queue_redraw()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("map") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_legend() -> void:
	_legend.clear()
	var lines: Array[String] = ["  Floor %d districts:" % GameState.floor_number]
	for zone in dungeon.zones_runtime.size():
		var color: Color = Dungeon.ZONE_MAP_COLORS[zone % 4]
		var info: Dictionary = dungeon.zones_runtime[zone]
		var known: bool = dungeon.zone_visited.has(zone)
		var display_name: String = info["name"] if known else "??? (unexplored)"
		var boss: Variant = info["boss"]
		var boss_note := ""
		if known:
			if boss != null and is_instance_valid(boss) and boss.hp > 0:
				boss_note = " — boss at large"
			else:
				boss_note = " — boss DEFEATED, district mapped"
		lines.append("  [color=%s]■[/color] %s%s" % [color.to_html(false), display_name, boss_note])
	_legend.append_text("\n".join(lines))


func _draw_map() -> void:
	if dungeon == null or not is_instance_valid(dungeon):
		return
	var grid := dungeon.grid
	var area := _canvas.size
	var scale := minf((area.x - 40) / grid.width, (area.y - 20) / grid.height)
	var origin := Vector2((area.x - grid.width * scale) / 2.0, (area.y - grid.height * scale) / 2.0)

	for y in grid.height:
		for x in grid.width:
			var pos := Vector2i(x, y)
			if not dungeon.explored.has(pos):
				continue
			var t := grid.get_tile(pos)
			var color: Color
			match t:
				DungeonGrid.WALL:
					color = Color(0.17, 0.15, 0.2)
				DungeonGrid.SAFE:
					color = Color(0.2, 0.55, 0.55)
				DungeonGrid.STAIRS:
					color = Color(0.9, 0.72, 0.3)
				_:
					var zone := dungeon.zone_at(pos)
					color = Dungeon.ZONE_MAP_COLORS[zone % 4].darkened(0.35) if zone != -1 else Color(0.42, 0.4, 0.47)
			_canvas.draw_rect(Rect2(origin + Vector2(pos) * scale, Vector2(scale, scale)), color)

	# Markers (only on explored tiles)
	if dungeon.shopkeeper != null and is_instance_valid(dungeon.shopkeeper) \
			and dungeon.explored.has(dungeon.shopkeeper.grid_pos):
		_draw_marker(origin, scale, dungeon.shopkeeper.grid_pos, Color(0.95, 0.8, 0.35))
	for info: Dictionary in dungeon.zones_runtime:
		var boss: Variant = info["boss"]
		if boss != null and is_instance_valid(boss) and boss.hp > 0 and dungeon.explored.has(boss.grid_pos):
			_draw_marker(origin, scale, boss.grid_pos, Color(1.0, 0.3, 0.25))
	_draw_marker(origin, scale, dungeon.player.grid_pos, Color.WHITE)


func _draw_marker(origin: Vector2, scale: float, pos: Vector2i, color: Color) -> void:
	var rect := Rect2(origin + Vector2(pos) * scale - Vector2(scale, scale) * 0.25,
		Vector2(scale, scale) * 1.5)
	_canvas.draw_rect(rect, color)
