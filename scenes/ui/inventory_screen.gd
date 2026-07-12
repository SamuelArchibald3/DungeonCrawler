class_name InventoryScreen
extends Control
## Modal inventory/equipment screen. Double-click (or Enter) an inventory
## item to equip/use it; activate an equipped row to unequip.

signal closed

var _inv_list: ItemList
var _equip_list: ItemList
var _detail: RichTextLabel
var _stats: RichTextLabel


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.09, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "CRAWLER INVENTORY  —  the System takes no responsibility for buyer's remorse"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	# Left: inventory
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	left.add_child(_make_header("Inventory (double-click to equip/use)"))
	_inv_list = ItemList.new()
	_inv_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_list.item_activated.connect(_on_inventory_activated)
	_inv_list.item_selected.connect(_on_inventory_selected)
	left.add_child(_inv_list)

	# Middle: equipment
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(mid)
	mid.add_child(_make_header("Equipped (double-click to unequip)"))
	_equip_list = ItemList.new()
	_equip_list.custom_minimum_size = Vector2(0, 140)
	_equip_list.item_activated.connect(_on_equipment_activated)
	_equip_list.item_selected.connect(_on_equipment_selected)
	mid.add_child(_equip_list)
	mid.add_child(_make_header("Item details"))
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_detail)

	# Right: character sheet
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	right.add_child(_make_header("Character"))
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_stats)

	var hint := Label.new()
	hint.text = "I / Esc — close"
	vbox.add_child(hint)


func _make_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	return label


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func refresh() -> void:
	var c: CharacterData = GameState.character
	_inv_list.clear()
	for item: ItemData in c.inventory:
		_inv_list.add_item(item.display_name() + item.level_tag())
		_inv_list.set_item_custom_fg_color(_inv_list.item_count - 1, Color(ItemData.RARITY_COLORS[item.rarity]))

	_equip_list.clear()
	for slot in CharacterData.EQUIP_SLOTS:
		var item = c.equipment[slot]
		var text := "%s: %s" % [slot, item.display_name() + item.level_tag() if item != null else "—"]
		_equip_list.add_item(text)
		if item != null:
			_equip_list.set_item_custom_fg_color(_equip_list.item_count - 1, Color(ItemData.RARITY_COLORS[item.rarity]))

	_stats.clear()
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % c.char_name)
	if c.race != null:
		lines.append("%s %s" % [c.race.display_name, c.char_class.display_name if c.char_class != null else ""])
	lines.append("Level %d   HP %d/%d" % [c.level, c.hp, c.max_hp])
	lines.append("")
	for stat in CharacterData.STAT_NAMES:
		lines.append("%s: %d" % [stat, c.get_stat(stat)])
	lines.append("")
	lines.append("Weapon damage: %d" % c.get_weapon_damage())
	lines.append("Defense: %d" % c.get_defense())
	for id in c.abilities:
		lines.append("%s — %s" % [Abilities.display_name(id), Abilities.description(id)])
	_stats.append_text("\n".join(lines))
	_detail.clear()


func _on_inventory_selected(index: int) -> void:
	var item: ItemData = GameState.character.inventory[index]
	_detail.clear()
	_detail.append_text(item.describe())

	# Side-by-side comparison with whatever is equipped in that slot
	if item.is_consumable():
		return
	var equipped = GameState.character.equipment.get(item.base.slot)
	if equipped == null:
		_detail.append_text("\n\n[color=#909090]Slot is empty — equipping is a strict upgrade. Even the System agrees.[/color]")
		return
	_detail.append_text("\n\n[color=#f0c040]— currently equipped —[/color]\n")
	_detail.append_text(equipped.describe())
	_detail.append_text("\n\n[color=#f0c040]— if you swap —[/color]\n")
	_detail.append_text(_comparison_text(item, equipped))


func _on_equipment_selected(index: int) -> void:
	var slot: StringName = CharacterData.EQUIP_SLOTS[index]
	var item = GameState.character.equipment[slot]
	_detail.clear()
	if item == null:
		_detail.append_text("[color=#909090]Nothing equipped in '%s'. Bold strategy.[/color]" % slot)
	else:
		_detail.append_text(item.describe())


## Stat deltas if `item` replaced `equipped` in the same slot.
func _comparison_text(item: ItemData, equipped: ItemData) -> String:
	var lines: Array[String] = []
	var pairs := [
		["Damage", item.get_damage() - equipped.get_damage(), item.base.slot == &"weapon"],
		["Defense", item.get_defense() - equipped.get_defense(), item.base.slot != &"weapon"],
	]
	for pair in pairs:
		if pair[2] and pair[1] != 0:
			lines.append(_delta_line(pair[0], pair[1]))
	for stat in CharacterData.STAT_NAMES:
		var delta: int = item.get_stat_bonus(stat) - equipped.get_stat_bonus(stat)
		if delta != 0:
			lines.append(_delta_line(String(stat), delta))
	if lines.is_empty():
		return "[color=#909090]No stat changes. Purely a fashion decision.[/color]"
	return "\n".join(lines)


func _delta_line(label: String, delta: int) -> String:
	var color := "#4fc14f" if delta > 0 else "#e05050"
	return "[color=%s]%s %+d[/color]" % [color, label, delta]


func _on_inventory_activated(index: int) -> void:
	var c: CharacterData = GameState.character
	var item: ItemData = c.inventory[index]

	if item.is_consumable():
		if item.base.id == &"healing_potion":
			if c.hp >= c.max_hp:
				Events.msg("You're at full HP. The potion judges you silently.", &"system")
				return
			c.inventory.remove_at(index)
			c.heal(floori(c.max_hp * 0.4))
			Events.msg("You drink the potion. %s" % item.base.flavor_text, &"loot")
		refresh()
		Events.hud_refresh.emit()
		return

	# Equip: swap with whatever is in the slot
	var slot: StringName = item.base.slot
	c.inventory.remove_at(index)
	var previous = c.equipment[slot]
	c.equipment[slot] = item
	if previous != null:
		c.inventory.append(previous)
	c.recompute_max_hp()  # CON gear affects max HP
	Events.msg("Equipped %s." % item.colored_name(), &"loot")
	Events.item_equipped.emit(item)
	refresh()
	Events.hud_refresh.emit()


func _on_equipment_activated(index: int) -> void:
	var c: CharacterData = GameState.character
	var slot: StringName = CharacterData.EQUIP_SLOTS[index]
	var item = c.equipment[slot]
	if item == null:
		return
	c.equipment[slot] = null
	c.inventory.append(item)
	c.recompute_max_hp()
	Events.msg("Unequipped %s." % item.display_name(), &"info")
	refresh()
	Events.hud_refresh.emit()
