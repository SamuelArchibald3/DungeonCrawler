class_name CharCreateScreen
extends Control
## Character creation: roll a random crawler or point-buy your own.

signal confirmed(character: CharacterData)

const POINT_POOL := 10
const STAT_MIN := 6
const STAT_MAX := 16

var _name_edit: LineEdit
var _stat_values := {}   # StringName -> int
var _stat_labels := {}   # StringName -> Label
var _plus_buttons := {}  # StringName -> Button
var _points_label: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CRAWLER REGISTRATION"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The dungeon opened. Your planet didn't make it. Sign here."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.68, 0.65))
	vbox.add_child(subtitle)

	# Name row
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	var reroll_name := Button.new()
	reroll_name.text = "Reroll Name"
	reroll_name.pressed.connect(func() -> void: _name_edit.text = Flavor.random_name(_rng))
	name_row.add_child(reroll_name)

	# Stat rows
	for stat in CharacterData.STAT_NAMES:
		_stat_values[stat] = 8
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var label := Label.new()
		label.text = String(stat)
		label.custom_minimum_size = Vector2(60, 0)
		row.add_child(label)
		var minus := Button.new()
		minus.text = "−"
		minus.pressed.connect(_on_stat_changed.bind(stat, -1))
		row.add_child(minus)
		var value := Label.new()
		value.text = "8"
		value.custom_minimum_size = Vector2(40, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		_stat_labels[stat] = value
		var plus := Button.new()
		plus.text = "+"
		plus.pressed.connect(_on_stat_changed.bind(stat, 1))
		row.add_child(plus)
		_plus_buttons[stat] = plus

	_points_label = Label.new()
	vbox.add_child(_points_label)

	# Action buttons
	var buttons_row := HBoxContainer.new()
	buttons_row.add_theme_constant_override("separation", 10)
	vbox.add_child(buttons_row)
	var roll := Button.new()
	roll.text = "Roll Random Crawler"
	roll.pressed.connect(_on_roll_random)
	buttons_row.add_child(roll)
	var reset := Button.new()
	reset.text = "Reset (Point Buy)"
	reset.pressed.connect(_on_reset)
	buttons_row.add_child(reset)

	var start := Button.new()
	start.text = "ENTER THE DUNGEON"
	start.custom_minimum_size = Vector2(0, 44)
	start.pressed.connect(_on_confirm)
	vbox.add_child(start)

	_on_roll_random()


func _points_spent() -> int:
	var spent := 0
	for stat in _stat_values:
		spent += _stat_values[stat] - 8
	return spent


func _refresh() -> void:
	for stat in _stat_values:
		_stat_labels[stat].text = str(_stat_values[stat])
	var remaining := POINT_POOL - _points_spent()
	if remaining >= 0:
		_points_label.text = "Points remaining: %d" % remaining
	else:
		_points_label.text = "Points remaining: 0 (randomly rolled — lucky you)"
	for stat in _plus_buttons:
		_plus_buttons[stat].disabled = remaining <= 0 or _stat_values[stat] >= STAT_MAX


func _on_stat_changed(stat: StringName, delta: int) -> void:
	var new_value: int = clampi(_stat_values[stat] + delta, STAT_MIN, STAT_MAX)
	if delta > 0 and _points_spent() >= POINT_POOL:
		return
	_stat_values[stat] = new_value
	_refresh()


func _on_roll_random() -> void:
	_name_edit.text = Flavor.random_name(_rng)
	var rolled := CharGenerator.roll_stats(_rng)
	for stat in rolled:
		_stat_values[stat] = rolled[stat]
	_refresh()


func _on_reset() -> void:
	for stat in _stat_values:
		_stat_values[stat] = 8
	_refresh()


func _on_confirm() -> void:
	var c := CharacterData.new()
	c.char_name = _name_edit.text.strip_edges()
	if c.char_name == "":
		c.char_name = Flavor.random_name(_rng)
	for stat in _stat_values:
		c.base_stats[stat] = _stat_values[stat]
	c.recompute_max_hp()
	c.hp = c.max_hp
	confirmed.emit(c)
