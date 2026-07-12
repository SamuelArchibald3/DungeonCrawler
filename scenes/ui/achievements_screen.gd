class_name AchievementsScreen
extends Control
## Trophy case (toggle V). Unlocks persist across crawlers; the System
## finds this hilarious.

signal closed

var _list: RichTextLabel


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.05, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 560)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ACHIEVEMENT ARCHIVE — your legacy, itemized"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_list = RichTextLabel.new()
	_list.bbcode_enabled = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_list)

	var hint := Label.new()
	hint.text = "V / Esc — close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func open() -> void:
	visible = true
	_list.clear()
	var lines: Array[String] = []
	var count := 0
	for id: StringName in Achievements.DEFS:
		var def: Array = Achievements.DEFS[id]
		if Achievements.is_unlocked(id):
			count += 1
			lines.append("[color=#f0c040]★ %s[/color] — %s" % [def[0], def[1]])
		else:
			lines.append("[color=#5a5a5a]☆ %s — %s[/color]" % [def[0], def[1]])
	lines.insert(0, "Unlocked: %d / %d\n" % [count, Achievements.DEFS.size()])
	_list.append_text("\n".join(lines))


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("achievements") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
