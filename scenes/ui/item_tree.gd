class_name ItemTree
extends Tree
## Reusable item table: Item | Type | (optional) Price. Column titles are
## clickable to sort; clicking the same title flips direction. Rows carry
## their source-array index as metadata so display order never desyncs
## activation from the underlying inventory/stock array.

signal item_row_activated(item_index: int)
signal item_row_selected(item_index: int)

const TYPE_ORDER: Array[StringName] = [&"weapon", &"head", &"chest", &"feet", &"trinket", &"consumable"]

var _items: Array = []
var _price_fn := Callable()
var _sort_column := -1
var _sort_ascending := true


func _ready() -> void:
	hide_root = true
	allow_reselect = true
	set_column_titles_visible(true)
	column_title_clicked.connect(_on_title_clicked)
	item_activated.connect(_emit_activated)
	item_selected.connect(_emit_selected)


## price_fn: Callable(ItemData) -> int; when valid, a sortable Price column appears.
func set_items(items: Array, price_fn: Callable = Callable()) -> void:
	_items = items
	_price_fn = price_fn
	columns = 3 if _price_fn.is_valid() else 2
	set_column_title(0, "Item")
	set_column_expand(0, true)
	set_column_title(1, "Type")
	set_column_expand(1, false)
	set_column_custom_minimum_width(1, 120)
	if _price_fn.is_valid():
		set_column_title(2, "Price")
		set_column_expand(2, false)
		set_column_custom_minimum_width(2, 76)
	_rebuild()


func _rebuild() -> void:
	clear()
	var root := create_item()
	for i: int in _display_order():
		var item: ItemData = _items[i]
		var row := create_item(root)
		row.set_text(0, item.display_name() + item.level_tag())
		row.set_custom_color(0, Color(ItemData.RARITY_COLORS[item.rarity]))
		row.set_text(1, item.type_label())
		row.set_custom_color(1, Color(0.6, 0.58, 0.55))
		if _price_fn.is_valid():
			row.set_text(2, "%d g" % _price_fn.call(item))
			row.set_custom_color(2, Color(0.94, 0.75, 0.25))
		row.set_metadata(0, i)


func _type_key(index: int) -> int:
	return TYPE_ORDER.find((_items[index] as ItemData).base.slot)


func _name_of(index: int) -> String:
	return (_items[index] as ItemData).display_name()


func _display_order() -> Array:
	var order: Array = range(_items.size())
	if _sort_column < 0:
		return order
	var asc := _sort_ascending
	match _sort_column:
		0:
			order.sort_custom(func(a: int, b: int) -> bool:
				return _name_of(a) < _name_of(b) if asc else _name_of(b) < _name_of(a))
		1:
			order.sort_custom(func(a: int, b: int) -> bool:
				var ka := _type_key(a)
				var kb := _type_key(b)
				if ka == kb:
					return _name_of(a) < _name_of(b)
				return ka < kb if asc else kb < ka)
		2:
			if _price_fn.is_valid():
				order.sort_custom(func(a: int, b: int) -> bool:
					var pa: int = _price_fn.call(_items[a])
					var pb: int = _price_fn.call(_items[b])
					return pa < pb if asc else pb < pa)
	return order


func _on_title_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if _sort_column == column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = column
		_sort_ascending = true
	_rebuild()


func _selected_source_index() -> int:
	var row := get_selected()
	return row.get_metadata(0) if row != null else -1


func _emit_activated() -> void:
	var index := _selected_source_index()
	if index >= 0:
		item_row_activated.emit(index)


func _emit_selected() -> void:
	var index := _selected_source_index()
	if index >= 0:
		item_row_selected.emit(index)
