class_name ShopScreen
extends Control
## Modal shop: buy from the Bopca's stock, sell from your inventory.
## CHA discounts purchases (2%/point over 8) and improves sale prices (1%).

signal closed

var _keeper: Shopkeeper
var _stock_list: ItemList
var _inv_list: ItemList
var _detail: RichTextLabel
var _gold_label: Label


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.04, 1.0)
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
	title.text = "BOPCA'S DISCOUNT DUNGEON EMPORIUM  —  all sales final, all deaths yours"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.35))
	vbox.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_gold_label)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(left)
	left.add_child(_make_header("For sale (double-click to buy)"))
	_stock_list = ItemList.new()
	_stock_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stock_list.item_activated.connect(_on_stock_activated)
	_stock_list.item_selected.connect(_on_stock_selected)
	left.add_child(_stock_list)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(mid)
	mid.add_child(_make_header("Item details"))
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(_detail)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	right.add_child(_make_header("Your stuff (double-click to sell)"))
	_inv_list = ItemList.new()
	_inv_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inv_list.item_activated.connect(_on_inv_activated)
	_inv_list.item_selected.connect(_on_inv_selected)
	right.add_child(_inv_list)

	var hint := Label.new()
	hint.text = "I / Esc — leave the shop"
	vbox.add_child(hint)


func _make_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.94, 0.75, 0.25))
	return label


func open_for(keeper: Shopkeeper) -> void:
	_keeper = keeper
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


func _cha() -> int:
	return GameState.character.get_stat(&"CHA")


func refresh() -> void:
	var c: CharacterData = GameState.character
	_gold_label.text = "Your gold: %d      (CHA %d adjusts prices — charm is currency)" % [c.gold, _cha()]

	_stock_list.clear()
	for item: ItemData in _keeper.stock:
		_stock_list.add_item("%s%s  —  %d g" % [item.display_name(), item.level_tag(), LootGenerator.buy_price(item, _cha())])
		_stock_list.set_item_custom_fg_color(_stock_list.item_count - 1, Color(ItemData.RARITY_COLORS[item.rarity]))

	_inv_list.clear()
	for item: ItemData in c.inventory:
		_inv_list.add_item("%s%s  —  %d g" % [item.display_name(), item.level_tag(), LootGenerator.sell_price(item, _cha())])
		_inv_list.set_item_custom_fg_color(_inv_list.item_count - 1, Color(ItemData.RARITY_COLORS[item.rarity]))

	_detail.clear()


func _on_stock_selected(index: int) -> void:
	var item: ItemData = _keeper.stock[index]
	_detail.clear()
	_detail.append_text(item.describe())
	_detail.append_text("\n\n[color=#f0c040]Buy price: %d gold[/color]" % LootGenerator.buy_price(item, _cha()))


func _on_inv_selected(index: int) -> void:
	var item: ItemData = GameState.character.inventory[index]
	_detail.clear()
	_detail.append_text(item.describe())
	_detail.append_text("\n\n[color=#f0c040]Sell price: %d gold[/color]" % LootGenerator.sell_price(item, _cha()))


func _on_stock_activated(index: int) -> void:
	var c: CharacterData = GameState.character
	var item: ItemData = _keeper.stock[index]
	var price := LootGenerator.buy_price(item, _cha())
	if c.gold < price:
		Events.msg("You can't afford that. The Bopca's sympathy is also not free.", &"system")
		return
	c.gold -= price
	_keeper.stock.remove_at(index)
	c.inventory.append(item)
	Events.msg("Bought %s for %d gold." % [item.colored_name(), price], &"loot")
	Events.item_bought.emit(_cha())
	refresh()
	Events.hud_refresh.emit()


func _on_inv_activated(index: int) -> void:
	var c: CharacterData = GameState.character
	var item: ItemData = c.inventory[index]
	var price := LootGenerator.sell_price(item, _cha())
	c.inventory.remove_at(index)
	c.gold += price
	Events.msg("Sold %s for %d gold. The Bopca will resell it for triple." % [item.display_name(), price], &"loot")
	Events.item_sold.emit()
	refresh()
	Events.hud_refresh.emit()
