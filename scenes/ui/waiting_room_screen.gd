class_name WaitingRoomScreen
extends Control
## The Stairwell Lounge: where a crawler who descended early waits, frozen,
## while the rest of the floor plays out at accelerated speed. Shows live
## counters, a kill feed, and a leaderboard until the floor ends, then a
## CONTINUE button to drop into the next floor with the survivors.

signal continue_pressed

var _dungeon: Dungeon
var _accum := 0.0
var _counters: Label
var _feed: RichTextLabel
var _board: RichTextLabel
var _status: Label
var _continue_button: Button


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "THE STAIRWELL LOUNGE — Sponsored by the Desperate"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var blurb := Label.new()
	blurb.text = "You descended early. The stairwell holds you until the floor above finishes eating everyone else."
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.add_theme_color_override("font_color", Color(0.7, 0.68, 0.65))
	vbox.add_child(blurb)

	_counters = Label.new()
	_counters.add_theme_font_size_override("font_size", 18)
	_counters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_counters)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	left.add_child(_header("Upstairs (live)"))
	_feed = RichTextLabel.new()
	_feed.bbcode_enabled = true
	_feed.scroll_following = true
	_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_feed)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	right.add_child(_header("Leaderboard"))
	_board = RichTextLabel.new()
	_board.bbcode_enabled = true
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_board)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color(0.6, 0.85, 0.95))
	vbox.add_child(_status)

	_continue_button = Button.new()
	_continue_button.text = "DESCEND WITH THE SURVIVORS"
	_continue_button.custom_minimum_size = Vector2(0, 44)
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())
	vbox.add_child(_continue_button)

	Events.crawler_event.connect(_on_crawler_event)
	Events.floor_state_changed.connect(_on_floor_state_changed)


func _header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	return label


func open(dungeon: Dungeon) -> void:
	_dungeon = dungeon
	_accum = 0.0
	_continue_button.visible = false
	_feed.clear()
	_feed.append_text("[color=#909090]You settle into a sticky chair. The show goes on above.[/color]\n")
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_dungeon = null


## Drive the floor at accelerated speed regardless of pacing mode.
func _process(delta: float) -> void:
	if not visible or _dungeon == null or not is_instance_valid(_dungeon):
		return
	if Crawlers.floor_state == Crawlers.FloorState.ENDED:
		return
	_accum += delta
	var step := TurnManager.WORLD_TICK_SECONDS / float(TurnManager.SPECTATE_MULT)
	while _accum >= step and Crawlers.floor_state != Crawlers.FloorState.ENDED:
		_accum -= step
		_dungeon.turn_manager.spectate_step()
	_refresh()


func _refresh() -> void:
	_counters.text = "%d crawlers alive · %d already below · floor timer %d" % [
		Crawlers.alive_count(), Crawlers.descended_count(), GameState.floor_turns_left]

	var ranked := Crawlers.roster.duplicate()
	ranked.sort_custom(func(a: CrawlerRecord, b: CrawlerRecord) -> bool:
		if a.alive != b.alive:
			return a.alive
		if a.sheet.level != b.sheet.level:
			return a.sheet.level > b.sheet.level
		return a.kills > b.kills)
	_board.clear()
	var shown := 0
	for cr: CrawlerRecord in ranked:
		if shown >= 10:
			break
		shown += 1
		var tag := "[color=#f0c040]YOU[/color] " if cr.is_player else ""
		var status := "" if cr.alive else " [color=#e05050](dead)[/color]"
		_board.append_text("%d. %s%s — Lv %d, %d kills%s\n" % [
			shown, tag, cr.sheet.char_name, cr.sheet.level, cr.kills, status])


func _on_crawler_event(kind: StringName, crawler: CrawlerRecord, _data: Dictionary) -> void:
	if not visible:
		return
	match kind:
		&"died":
			_feed.append_text("[color=#e05050]%s has died. %d remain.[/color]\n" % [
				crawler.sheet.char_name, Crawlers.alive_count()])
		&"descended":
			if not crawler.is_player:
				_feed.append_text("[color=#909090]%s reached the stairs.[/color]\n" % crawler.sheet.char_name)


func _on_floor_state_changed(new_state: int) -> void:
	if not visible:
		return
	if new_state == Crawlers.FloorState.ENDED:
		var placement := Crawlers.placement(Crawlers.player_record())
		_status.text = "The floor is closed. You survived it — placing #%d of %d." % [
			placement, Crawlers.roster.size()]
		_continue_button.visible = true
		_refresh()
