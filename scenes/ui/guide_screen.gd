class_name GuideScreen
extends Control
## Paged tutorial delivered by the saferoom guide, in System-snark voice.

signal closed

const PAGES := [
	["SO YOU'RE GOING TO DIE IN A DUNGEON",
		"Welcome, crawler. I'm contractually required to help you.\n\n" +
		"• Move with [b]WASD[/b] or the arrow keys. Every step is a turn; the dungeon moves when you do.\n" +
		"• Walk INTO a monster to hit it. Violence is the dungeon's love language.\n" +
		"• [b]Space[/b] waits a turn. Sometimes the bravest move is standing very still.\n" +
		"• Find the gold stairs tile and step on it to descend. Down is the only way out. Well — 'out.'"],
	["LOOT BOXES AND OTHER BRIBES",
		"Those colorful boxes? Bump them open. Bronze, Silver, Gold, Platinum — fancier box, fancier garbage.\n\n" +
		"• Gear goes in your inventory ([b]I[/b] or [b]Tab[/b]). Double-click to equip.\n" +
		"• Selecting an item shows what you'd gain or lose versus what's equipped. Green good. Red bad. You're welcome.\n" +
		"• Rarity runs Common → Uncommon → Rare → Epic → Legendary. Legendary crocs exist. I've seen them."],
	["THE FLOOR IS TEMPORARY",
		"Every floor has a timer — watch the countdown up top.\n\n" +
		"• When it hits zero, the floor closes and the ceiling starts introducing itself to your skull, harder each turn.\n" +
		"• The System calls this 'incentivized descent.' We call it 'the ceiling thing.'\n" +
		"• Kill, loot, descend. Dawdling is a lifestyle choice with a short shelf life."],
	["SAFE ROOMS (LIKE THIS ONE)",
		"Teal tiles are System-certified Safe Rooms™.\n\n" +
		"• Monsters legally cannot enter. They will absolutely camp the doorway like unpaid interns.\n" +
		"• You heal a little every turn inside, and the ceiling can't crush you here — even after the floor closes.\n" +
		"• Level-up stat points can only be allocated in here (open your inventory). Union rules.\n" +
		"• The timer keeps ticking, though. Safety is not the same as progress. Ask my therapist."],
	["THE FLOOR 3 REBRAND",
		"Reach floor 3 and the System offers you a new race and class. In here, thankfully.\n\n" +
		"• Three races, three classes, pick one of each. Stats change, you get an ability, your DNA files a complaint.\n" +
		"• Passives just work. Actives fire on [b]Q[/b] and have cooldowns.\n" +
		"• Choices are permanent. The System's refund department is a mural of a shredder."],
	["COMMERCE, CRAWLER-STYLE",
		"My cousin runs a shop somewhere on every floor. Look for the golden [b]B[/b].\n\n" +
		"• Monsters and boxes drop gold. Bump the shopkeeper to trade.\n" +
		"• Charisma gets you discounts. Yes, the dungeon rewards being pretty. No, it isn't fair.\n" +
		"• He buys your junk at insulting prices. He is also the only buyer. Welcome to economics."],
]

var _page := 0
var _title: Label
var _body: RichTextLabel
var _page_label: Label
var _quest_label: RichTextLabel
var _quest_button: Button
var _dungeon: Dungeon


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.08, 0.09, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 420)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Quest panel: the guide moonlights as a quest dispenser
	var quest_box := PanelContainer.new()
	vbox.add_child(quest_box)
	var quest_row := HBoxContainer.new()
	quest_row.add_theme_constant_override("separation", 12)
	quest_box.add_child(quest_row)
	_quest_label = RichTextLabel.new()
	_quest_label.bbcode_enabled = true
	_quest_label.fit_content = true
	_quest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_row.add_child(_quest_label)
	_quest_button = Button.new()
	_quest_button.custom_minimum_size = Vector2(150, 0)
	_quest_button.pressed.connect(_on_quest_button)
	quest_row.add_child(_quest_button)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", Color(0.45, 0.85, 0.9))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	vbox.add_child(nav)

	var prev := Button.new()
	prev.text = "< Prev"
	prev.pressed.connect(_prev_page)
	nav.add_child(prev)

	_page_label = Label.new()
	nav.add_child(_page_label)

	var next := Button.new()
	next.text = "Next >"
	next.pressed.connect(_next_page)
	nav.add_child(next)

	var close_button := Button.new()
	close_button.text = "That's enough help"
	close_button.pressed.connect(close)
	nav.add_child(close_button)


func open(dungeon: Dungeon = null) -> void:
	_page = 0
	_dungeon = dungeon
	if dungeon != null:
		Quests.offer(dungeon)
	visible = true
	_render()
	_render_quest()


func _render_quest() -> void:
	_quest_label.clear()
	match Quests.state:
		Quests.QState.OFFERED:
			_quest_label.append_text("[color=#f0c040]JOB POSTING:[/color] %s  [color=#4fc14f](+%d gold)[/color]" % [
				Quests.data["desc"], Quests.data["reward_gold"]])
			_quest_button.text = "Accept"
			_quest_button.disabled = false
		Quests.QState.ACTIVE:
			_quest_label.append_text("In progress: %s (%d/%d)" % [
				Quests.data["desc"], Quests.data["count"], Quests.data["needed"]])
			_quest_button.text = "Working on it"
			_quest_button.disabled = true
		Quests.QState.COMPLETE:
			_quest_label.append_text("[color=#4fc14f]COMPLETE:[/color] %s" % Quests.data["desc"])
			_quest_button.text = "Claim %d gold" % Quests.data["reward_gold"]
			_quest_button.disabled = false
		Quests.QState.CLAIMED:
			_quest_label.append_text("[color=#909090]No more work today. The guide is 'on break'.[/color]")
			_quest_button.text = "—"
			_quest_button.disabled = true
		_:
			_quest_label.append_text("[color=#909090]No postings. The dungeon economy is resting.[/color]")
			_quest_button.text = "—"
			_quest_button.disabled = true


func _on_quest_button() -> void:
	match Quests.state:
		Quests.QState.OFFERED:
			Quests.accept()
		Quests.QState.COMPLETE:
			Quests.claim()
	_render_quest()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		close()


func _prev_page() -> void:
	_page = maxi(_page - 1, 0)
	_render()


func _next_page() -> void:
	_page = mini(_page + 1, PAGES.size() - 1)
	_render()


func _render() -> void:
	_title.text = PAGES[_page][0]
	_body.clear()
	_body.append_text(PAGES[_page][1])
	_page_label.text = "%d / %d" % [_page + 1, PAGES.size()]
