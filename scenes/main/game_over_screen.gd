class_name GameOverScreen
extends Control
## Run summary + System eulogy. Permadeath means we just never saved anything.

signal new_crawler_requested

var _eulogy: Label
var _summary: Label


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.02, 0.03, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = "YOU DIED."
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_eulogy = Label.new()
	_eulogy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eulogy.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	vbox.add_child(_eulogy)

	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_summary)

	var button := Button.new()
	button.text = "NEW CRAWLER"
	button.custom_minimum_size = Vector2(220, 44)
	button.pressed.connect(func() -> void: new_crawler_requested.emit())
	vbox.add_child(button)


func open() -> void:
	var c: CharacterData = GameState.character
	_eulogy.text = Flavor.eulogy()
	var lines := "%s — Level %d\nFloor reached: %d    Kills: %d    Boxes opened: %d    Gold hoarded: %d\nFinal viewership: %d" % [
		c.char_name, c.level, GameState.floor_number, GameState.kills, GameState.boxes_opened, c.gold, Fame.viewers]
	if GameState.best_item_name != "":
		lines += "\nBest loot: %s (%s)" % [GameState.best_item_name, ItemData.RARITY_NAMES[GameState.best_item_rarity]]
	if Achievements.run_unlocks > 0:
		lines += "\nAchievements earned this run: %d" % Achievements.run_unlocks
	_summary.text = lines
	visible = true


func close() -> void:
	visible = false
