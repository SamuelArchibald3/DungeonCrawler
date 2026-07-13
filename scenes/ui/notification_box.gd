class_name NotificationBox
extends Control
## The System's pop-up notification box: top-center, queued, non-blocking.

const SHOW_TIME := 3.2
const BOX_WIDTH := 560.0

var _queue: Array = []  # [[title, body], ...]
var _timer := 0.0
var _panel: PanelContainer
var _title: Label
var _body: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(BOX_WIDTH, 0)
	_panel.position = Vector2((1280.0 - BOX_WIDTH) / 2.0, 46)
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	vbox.add_child(_title)

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_body)

	Events.announce.connect(push_notification)


func push_notification(title: String, body: String) -> void:
	_queue.append([title, body])


func queue_size() -> int:
	return _queue.size() + (1 if _panel.visible else 0)


func _process(delta: float) -> void:
	if _panel.visible:
		_timer -= delta
		if _timer <= 0.0:
			_panel.visible = false
	elif not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_title.text = next[0]
		_body.text = next[1]
		_panel.visible = true
		_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
		_timer = SHOW_TIME
