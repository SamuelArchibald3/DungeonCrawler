class_name Hud
extends PanelContainer
## Top-left HUD: HP/XP, level, floor, weapon, active ability cooldown.

var _name_label: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _xp_label: Label
var _floor_label: Label
var _timer_label: Label
var _weapon_label: Label
var _gold_label: Label
var _viewers_label: Label
var _ability_label: Label
var _quest_label: Label


func _ready() -> void:
	position = Vector2(8, 8)
	custom_minimum_size = Vector2(240, 0)

	var vbox := VBoxContainer.new()
	add_child(vbox)

	_name_label = Label.new()
	vbox.add_child(_name_label)

	_hp_label = Label.new()
	vbox.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(220, 10)
	_hp_bar.show_percentage = false
	_hp_bar.modulate = Color(0.9, 0.3, 0.3)
	vbox.add_child(_hp_bar)

	_xp_label = Label.new()
	vbox.add_child(_xp_label)

	_floor_label = Label.new()
	vbox.add_child(_floor_label)

	_timer_label = Label.new()
	vbox.add_child(_timer_label)

	_weapon_label = Label.new()
	vbox.add_child(_weapon_label)

	_gold_label = Label.new()
	vbox.add_child(_gold_label)

	_viewers_label = Label.new()
	_viewers_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.75))
	vbox.add_child(_viewers_label)

	_ability_label = Label.new()
	vbox.add_child(_ability_label)

	_quest_label = Label.new()
	_quest_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.95))
	vbox.add_child(_quest_label)

	Events.hud_refresh.connect(refresh)
	Events.floor_changed.connect(func(_n: int) -> void: refresh())
	Events.level_up.connect(func(_n: int) -> void: refresh())
	Events.viewers_changed.connect(func(_n: int) -> void: refresh())
	refresh()


func refresh() -> void:
	var c: CharacterData = GameState.character
	if c == null:
		return
	var title := c.char_name
	if c.race != null:
		title += "  [%s %s]" % [c.race.display_name, c.char_class.display_name if c.char_class != null else ""]
	_name_label.text = title
	_hp_label.text = "HP %d / %d" % [c.hp, c.max_hp]
	_hp_bar.max_value = c.max_hp
	_hp_bar.value = c.hp
	_xp_label.text = "Level %d   XP %d / %d" % [c.level, c.xp, c.xp_to_next()]
	_floor_label.text = "Floor %d" % GameState.floor_number
	var turns: int = GameState.floor_turns_left
	if turns <= 0:
		_timer_label.text = "FLOOR CLOSED — RUN."
		_timer_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.15))
	else:
		_timer_label.text = "Floor closes in: %d" % turns
		if turns <= 25:
			_timer_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.15))
		elif turns <= 100:
			_timer_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
		else:
			_timer_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_weapon_label.text = "Weapon: %s" % (c.equipment[&"weapon"].display_name() if c.equipment[&"weapon"] != null else "Fists")
	_gold_label.text = "Gold: %d" % c.gold
	_viewers_label.text = "Viewers: %s" % Fame.format_viewers(Fame.viewers)

	var quest_line := Quests.status_line()
	_quest_label.text = quest_line
	_quest_label.visible = quest_line != ""

	var active := Abilities.first_active(c)
	if active == &"":
		_ability_label.text = "Ability: —"
	else:
		var cd: int = c.ability_cooldowns.get(active, 0)
		if cd > 0:
			_ability_label.text = "Q: %s (CD %d)" % [Abilities.display_name(active), cd]
		else:
			_ability_label.text = "Q: %s (ready)" % Abilities.display_name(active)
