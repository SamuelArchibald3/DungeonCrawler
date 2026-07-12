class_name MessageLog
extends PanelContainer
## Bottom-left scrolling log. Categories map to colors; `system` gold is the
## future System AI voice slot. Loot messages carry their own BBCode colors.

const CATEGORY_COLORS := {
	&"combat": "#d8d8d8",
	&"loot": "#c8b878",
	&"system": "#f0c040",
	&"info": "#909090",
}

var _text: RichTextLabel


func _ready() -> void:
	custom_minimum_size = Vector2(620, 120)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	position = Vector2(8, 720 - 128)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.custom_minimum_size = Vector2(600, 104)
	add_child(_text)

	Events.message.connect(_on_message)


func _on_message(text: String, category: StringName) -> void:
	var color: String = CATEGORY_COLORS.get(category, "#c0c0c0")
	_text.append_text("[color=%s]%s[/color]\n" % [color, text])
