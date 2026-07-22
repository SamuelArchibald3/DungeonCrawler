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
	Events.crawler_event.connect(_on_crawler_event)


## The cohort kill feed.
func _on_crawler_event(kind: StringName, crawler: CrawlerRecord, data: Dictionary) -> void:
	match kind:
		&"died":
			var line := "Crawler %s has died. %d remain." % [crawler.sheet.char_name, Crawlers.alive_count()]
			var killer: Variant = data.get("killer")
			if killer != null and killer is CrawlerRecord and (killer as CrawlerRecord).is_player:
				line = "You killed Crawler %s. %d remain. The viewers are ELECTRIC." % [
					crawler.sheet.char_name, Crawlers.alive_count()]
			_text.append_text("[color=#e05050]%s[/color]\n" % line)
		&"pvp_kill":
			_text.append_text("[color=#e05050]Crawler-on-crawler violence: %s. The System approves.[/color]\n" % str(data.get("summary", "")))
		&"descended":
			if crawler.is_player:
				return  # the player gets their own descent message
			_text.append_text("[color=#909090]Crawler %s has taken the stairs. %d below.[/color]\n" % [
				crawler.sheet.char_name, Crawlers.descended_count()])
		&"emote":
			_text.append_text("[color=#7fd8e8]%s[/color]\n" % Flavor.emote(crawler.sheet.char_name))


func _on_message(text: String, category: StringName) -> void:
	var color: String = CATEGORY_COLORS.get(category, "#c0c0c0")
	_text.append_text("[color=%s]%s[/color]\n" % [color, text])
