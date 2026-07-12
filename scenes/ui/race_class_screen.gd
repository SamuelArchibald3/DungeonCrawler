class_name RaceClassScreen
extends Control
## The level-3 selection event: pick 1 of 3 races, then 1 of 3 classes.
## The System is legally required to offer you options.

signal done

var _title: Label
var _cards_box: HBoxContainer
var _phase := 0  # 0 = race, 1 = class
var _chosen_race: RaceDef
var _chosen_class: ClassDef


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.1, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	vbox.add_child(_title)

	var subtitle := Label.new()
	subtitle.text = "Choices are final. Refunds are a myth invented by dead crawlers."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	_cards_box = HBoxContainer.new()
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.add_theme_constant_override("separation", 24)
	vbox.add_child(_cards_box)


func open() -> void:
	visible = true
	_phase = 0
	Events.msg("CONGRATULATIONS, CRAWLER. You have reached Floor 3. Please select your PERMANENT BIOLOGICAL REBRAND.", &"system")
	_show_race_options()


func _show_race_options() -> void:
	_title.text = "SELECT YOUR NEW RACE"
	var pool := RaceDef.all()
	_fill_cards(_pick_three(pool), _on_race_picked)


func _show_class_options() -> void:
	_title.text = "SELECT YOUR CLASS"
	var pool := ClassDef.all()
	_fill_cards(_pick_three(pool), _on_class_picked)


func _pick_three(pool: Array) -> Array:
	var shuffled := pool.duplicate()
	# Deterministic per-run shuffle using the run RNG
	for i in range(shuffled.size() - 1, 0, -1):
		var j := GameState.rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	return shuffled.slice(0, 3)


func _fill_cards(options: Array, on_pick: Callable) -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	for def in options:
		_cards_box.add_child(_make_card(def, on_pick))


func _make_card(def: Resource, on_pick: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 300)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = def.display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var stats_parts: Array[String] = []
	for stat in def.stat_mods:
		stats_parts.append("%s %+d" % [stat, def.stat_mods[stat]])
	if def.max_hp_mod != 0:
		stats_parts.append("HP %+d" % def.max_hp_mod)
	var stats_label := Label.new()
	stats_label.text = ", ".join(stats_parts) if not stats_parts.is_empty() else "No stat changes"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
	vbox.add_child(stats_label)

	var ability_label := Label.new()
	ability_label.text = "%s — %s" % [Abilities.display_name(def.ability_id), Abilities.description(def.ability_id)]
	ability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ability_label.add_theme_color_override("font_color", Color(0.5, 0.75, 0.95))
	vbox.add_child(ability_label)

	var desc_label := Label.new()
	desc_label.text = def.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	vbox.add_child(desc_label)

	var button := Button.new()
	button.text = "SELECT"
	button.pressed.connect(func() -> void: on_pick.call(def))
	vbox.add_child(button)
	return card


func _on_race_picked(def: RaceDef) -> void:
	_chosen_race = def
	Events.msg("Race selected: %s. Your DNA files a complaint." % def.display_name, &"system")
	_phase = 1
	_show_class_options()


func _on_class_picked(def: ClassDef) -> void:
	_chosen_class = def
	_apply_choices()


func _apply_choices() -> void:
	var c: CharacterData = GameState.character
	c.race = _chosen_race
	c.char_class = _chosen_class
	for def in [_chosen_race, _chosen_class]:
		if not c.abilities.has(def.ability_id):
			c.abilities.append(def.ability_id)
	c.recompute_max_hp()
	c.hp = c.max_hp  # full rebuild, full heal
	GameState.race_class_done = true
	Events.msg("RACE AND CLASS ASSIGNED: %s %s. NO REFUNDS." % [_chosen_race.display_name, _chosen_class.display_name], &"system")
	Events.race_class_completed.emit()
	Events.hud_refresh.emit()
	visible = false
	done.emit()


## Used by the headless chaos test to click through the modal.
func debug_pick_random() -> void:
	if not visible:
		return
	var buttons: Array[Button] = []
	_collect_buttons(_cards_box, buttons)
	if not buttons.is_empty():
		buttons[randi() % buttons.size()].pressed.emit()


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons(child, out)
